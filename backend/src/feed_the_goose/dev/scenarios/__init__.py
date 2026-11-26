"""The seed scenarios (TDD §5.10). Synthetic data only.

A scenario writes a user's inputs: day settings, habits, logs, and the first day row
with an explicit window and starting lead. The days after it are created and settled by
`ensure_days` on the user's first chase read, by the same rules as every other day, so
no result is written by hand.

Windows are placed relative to the real time, so no clock needs changing: the day's
start is chosen, to the minute, so that the day under way began a set time ago.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from fractions import Fraction
from uuid import uuid4
from zoneinfo import ZoneInfo

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.domain.day import (
    DaySettings,
    DayWindow,
    date_of,
    day_window,
    hours_between,
)
from feed_the_goose.models import Day, Habit, Log, User
from feed_the_goose.models import DaySettings as DaySettingsRow
from feed_the_goose.repositories.day_settings import DaySettingsRepository
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.repositories.habits import HabitRepository
from feed_the_goose.repositories.logs import LogRepository

TIME_ZONE = "America/New_York"
DAY_HOURS = 18
# Name, unit, target and chunk, as in the TDD §5.3 example day.
HABITS = [
    ("Pushups", "reps", 50, 10),
    ("Workout", "minutes", 30, 10),
    ("Reading", "pages", 20, 5),
]
# Minutes between a day's start and its first log, and between its logs.
LOG_SPACING = timedelta(minutes=20)


@dataclass
class Seeding:
    """Writes one user's rows. The caller has added the user and commits."""

    db: AsyncSession
    user: User
    now: datetime
    steps_per_day: int
    # For `caught-soon`: how long after seeding the catch happens.
    delay: timedelta
    day: DaySettings | None = None

    def place(self, gone: Fraction) -> date:
        """Use a day of `DAY_HOURS` by the local clock of which the fraction `gone`
        has passed, to the minute, and return its date. Across a clock change the
        day's real length differs, so the start is placed again from it."""
        hours = Fraction(DAY_HOURS)
        for _ in range(2):
            elapsed = timedelta(hours=float(hours * gone))
            start = (self.now - elapsed).astimezone(ZoneInfo(TIME_ZONE))
            start = start.replace(second=0, microsecond=0)
            end = start + timedelta(hours=DAY_HOURS)
            self.day = DaySettings(TIME_ZONE, start.time(), end.time())
            today = date_of(self.now, lambda _: self._settings)
            window = self.window(today)
            hours = hours_between(window.starts_at, window.ends_at)
        return today

    def window(self, day: date) -> DayWindow:
        return day_window(day, self._settings, steps_per_day=self.steps_per_day)

    async def start(self, first: date, starting_lead: Fraction | None) -> list[Habit]:
        """Write the day settings from before `first`, and the three habits from
        `first`. With a starting lead, also write `first` as the first day."""
        settings = self._settings
        await DaySettingsRepository(self.db).add(
            DaySettingsRow(
                user_id=self.user.id,
                effective_from=first - timedelta(days=1),
                time_zone=settings.time_zone,
                day_start=settings.day_start,
                day_end=settings.day_end,
                created_at=self.now,
            )
        )
        window = self.window(first)
        habits = [
            await HabitRepository(self.db).add(
                Habit(
                    user_id=self.user.id,
                    name=name,
                    unit=unit,
                    chunk=chunk,
                    position=position,
                    effective_from=first,
                    archived_from=None,
                    created_at=window.starts_at - timedelta(hours=1),
                ),
                target,
            )
            for position, (name, unit, target, chunk) in enumerate(HABITS)
        ]
        if starting_lead is not None:
            await DayRepository(self.db).add(
                Day(
                    user_id=self.user.id,
                    date=first,
                    starts_at=window.starts_at,
                    ends_at=window.ends_at,
                    starting_lead=starting_lead,
                )
            )
        return habits

    async def log(self, day: date, amounts: list[tuple[Habit, int]]) -> None:
        """Log each amount in chunks, one every `LOG_SPACING` from the day's start."""
        at = self.window(day).starts_at
        for habit, amount in amounts:
            for _ in range(amount // habit.chunk):
                at += LOG_SPACING
                await LogRepository(self.db).insert(
                    Log(
                        id=uuid4(),
                        user_id=self.user.id,
                        habit_id=habit.id,
                        amount=habit.chunk,
                        logged_at=at,
                        received_at=at,
                        source="app",
                        date=day,
                    )
                )

    async def publish(self, handle: str) -> None:
        """Publish the profile at `handle`, taking it from any other user."""
        await self.db.execute(
            update(User)
            .where(User.handle == handle, User.id != self.user.id)
            .values(handle=None, public=False)
        )
        self.user.handle = handle
        self.user.public = True
        await self.db.flush()

    @property
    def _settings(self) -> DaySettings:
        assert self.day is not None, "place the day first"
        return self.day


async def fresh(s: Seeding) -> None:
    """A user with no habits, on the default day hours."""
    s.day = DaySettings(TIME_ZONE, time(6), time(0))
    local_date = s.now.astimezone(ZoneInfo(TIME_ZONE)).date()
    await DaySettingsRepository(s.db).add(
        DaySettingsRow(
            user_id=s.user.id,
            effective_from=local_date - timedelta(days=1),
            time_zone=TIME_ZONE,
            day_start=s.day.day_start,
            day_end=s.day.day_end,
            created_at=s.now,
        )
    )


async def demo(s: Seeding) -> None:
    """34 settled days, 31 complete, 2 short and 1 caught 14 days ago, so the streak
    is 13. Today is two thirds gone with Pushups 20 and Workout 30 logged, so the
    lead is 100 + 46.7 − 66.7 = 80. Profile public at `matt`."""
    today = s.place(Fraction(2, 3))
    first = today - timedelta(days=34)
    pushups, workout, reading = await s.start(first, Fraction(s.steps_per_day))
    for ago in range(34, 0, -1):
        if ago == 14:
            continue  # nothing logged, so the pursuer catches up at the day's end
        finished = [(pushups, 50), (workout, 30)]
        if ago not in (20, 27):  # short days leave Reading undone
            finished.append((reading, 20))
        await s.log(today - timedelta(days=ago), finished)
    await s.log(today, [(pushups, 20), (workout, 30)])
    s.user.display_name = "Matt"
    await s.publish("matt")


async def caught_soon(s: Seeding) -> None:
    """Yesterday was short, and today's starting lead is what the pursuer walks
    between today's start and `delay` after seeding, so it catches up then."""
    today = s.place(Fraction(1, DAY_HOURS))
    yesterday = today - timedelta(days=1)
    window = s.window(today)
    lead = window.steps_per_hour * hours_between(window.starts_at, s.now + s.delay)
    # Yesterday Pushups and Workout are finished, two shares of three, and the
    # pursuer walks the whole day, so it ends short with `lead` left.
    earned = Fraction(s.steps_per_day * 2, len(HABITS))
    pushups, workout, _ = await s.start(yesterday, lead + s.steps_per_day - earned)
    await s.log(yesterday, [(pushups, 50), (workout, 30)])


async def almost_complete(s: Seeding) -> None:
    """Today, every habit is one chunk short of its target."""
    today = s.place(Fraction(1, 2))
    habits = await s.start(today, Fraction(s.steps_per_day))
    await s.log(
        today,
        [
            (habit, target - chunk)
            for habit, (_, _, target, chunk) in zip(habits, HABITS, strict=True)
        ],
    )


SCENARIOS: dict[str, Callable[[Seeding], Awaitable[None]]] = {
    "fresh": fresh,
    "demo": demo,
    "caught-soon": caught_soon,
    "almost-complete": almost_complete,
}
