"""Days and settlement (TDD §5.4, constitution §4).

`ensure_days` runs first in every chase read and write, inside the caller's
transaction, with the user's row locked. It creates the days that have started and
settles each one whose successor has started. A settled day is never rewritten.
"""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from fractions import Fraction
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.config import Settings
from feed_the_goose.domain import chase as rules
from feed_the_goose.domain.day import DaySettings, DayWindow, date_of, day_window
from feed_the_goose.domain.streak import starting_lead_after, streak_after
from feed_the_goose.models import Day, Habit, Log, User
from feed_the_goose.models import DaySettings as DaySettingsRow
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.repositories.habits import HabitRepository
from feed_the_goose.repositories.logs import LogRepository
from feed_the_goose.repositories.users import UserRepository
from feed_the_goose.services.accounts import current_day


class RefusedError(Exception):
    """A request the rules refuse. The days ensured before it are still kept."""


@dataclass(frozen=True)
class DayHabit:
    """A habit of a day and the target that applies to that day."""

    habit: Habit
    target: int


class Calendar:
    """A user's day settings and habits: which days exist and when they run."""

    def __init__(
        self,
        settings_rows: list[DaySettingsRow],
        habits: list[tuple[Habit, list[tuple[date, int]]]],
        *,
        steps_per_day: int,
    ) -> None:
        # Oldest first. Every user has a row from sign-up.
        self._settings = settings_rows
        # Each habit with its targets, oldest first, in position order.
        self._habits = habits
        self._steps_per_day = steps_per_day

    def settings_for(self, day: date) -> DaySettings:
        """The settings in effect on `day`. Dates before the first row use it."""
        row = next(
            (r for r in reversed(self._settings) if r.effective_from <= day),
            self._settings[0],
        )
        return DaySettings(row.time_zone, row.day_start, row.day_end)

    def habits_on(self, day: date) -> list[DayHabit]:
        """The habits that belong to `day`, with that day's targets."""
        found = []
        for habit, targets in self._habits:
            if habit.effective_from > day or (
                habit.archived_from is not None and habit.archived_from <= day
            ):
                continue
            target = next((t for since, t in reversed(targets) if since <= day), None)
            if target is not None:
                found.append(DayHabit(habit, target))
        return found

    def first_habit_date(self) -> date | None:
        return min((h.effective_from for h, _ in self._habits), default=None)

    def first_habit_created_at(self) -> datetime | None:
        return min((h.created_at for h, _ in self._habits), default=None)

    def date_of(self, instant: datetime) -> date:
        """The day an instant belongs to; during the night, the day that ended."""
        return date_of(instant, self.settings_for)

    def window(self, day: date, *, not_before: datetime | None = None) -> DayWindow:
        return day_window(
            day,
            self.settings_for(day),
            steps_per_day=self._steps_per_day,
            not_before=not_before,
        )

    def stored_window(self, row: Day) -> DayWindow:
        """A stored day's window. The pace comes from its settings, so a first day
        that started late keeps the normal pace."""
        return DayWindow(
            date=row.date,
            starts_at=row.starts_at,
            ends_at=row.ends_at,
            steps_per_hour=self.window(row.date).steps_per_hour,
        )

    def next_day_starts_at(self, row: Day) -> datetime:
        """When the day after `row` starts, which is when `row` settles."""
        return self.window(
            row.date + timedelta(days=1), not_before=row.ends_at
        ).starts_at


@dataclass(frozen=True)
class DayRecord:
    """A stored day with the habits and logs its chase is computed from."""

    row: Day
    window: DayWindow
    next_day_starts_at: datetime
    habits: list[DayHabit]
    # Every log of the day, undone ones included, in the order they count.
    logs: list[Log]
    # The streak after the latest settled day before this one.
    streak_before: int
    steps_per_day: int

    def chase_at(
        self, at: datetime, *, counting: Log | None = None
    ) -> rules.ChaseState:
        """The chase at `at` from the logs that are not undone, plus `counting`."""
        ids = {h.habit.id for h in self.habits}
        entries = [
            rules.LogEntry(str(log.id), str(log.habit_id), log.amount, log.logged_at)
            for log in self.logs
            if (log.undone_at is None or log is counting) and log.habit_id in ids
        ]
        return rules.chase_at(
            self.window,
            self.row.starting_lead,
            [rules.HabitTarget(str(h.habit.id), h.target) for h in self.habits],
            entries,
            at,
            steps_per_day=self.steps_per_day,
        )

    def final(self, *, counting: Log | None = None) -> rules.ChaseState:
        """The chase once every log of the day has counted."""
        last = max((log.logged_at for log in self.logs), default=self.row.ends_at)
        return self.chase_at(max(self.next_day_starts_at, last), counting=counting)

    def outcome(self, log: Log) -> rules.LogOutcome:
        """What `log` earns, or earned before it was undone. A log's outcome
        depends only on the logs before it, so it is the same on every replay."""
        found = self.final(counting=log).outcomes
        return next(o for o in found if o.log_id == str(log.id))

    def steps_by_log(self) -> dict[UUID, Fraction]:
        """What each log counts for now: its earnings, or 0 once undone."""
        earned = {UUID(o.log_id): o.steps for o in self.final().outcomes}
        return {log.id: earned.get(log.id, Fraction(0)) for log in self.logs}


@dataclass(frozen=True)
class Ensured:
    """The locked user, their calendar, and the current day, if it has habits."""

    user: User
    calendar: Calendar
    current: Day | None


class DaysService:
    def __init__(
        self, *, settings: Settings, sessions: async_sessionmaker[AsyncSession]
    ) -> None:
        self._settings = settings
        self._sessions = sessions

    @asynccontextmanager
    async def transaction(
        self, user_id: UUID, now: datetime
    ) -> AsyncGenerator[tuple[AsyncSession, Ensured]]:
        """One transaction with the user's row locked and the days ensured.

        It commits when the block ends or raises a `RefusedError`, so a refused
        request still keeps the days it settled, and rolls back on anything else.
        """
        async with self._sessions() as db:
            transaction = await db.begin()
            try:
                yield db, await self.ensure_days(db, user_id, now)
            except RefusedError:
                await transaction.commit()
                raise
            except BaseException:
                await transaction.rollback()
                raise
            await transaction.commit()

    async def ensure_days(
        self, db: AsyncSession, user_id: UUID, now: datetime
    ) -> Ensured:
        """Lock the user, create the days that have started up to `now` and settle
        each day whose successor has started, in date order.

        A date with no habit gets no day; the streak and the carried lead pass
        over it. The current day is the one `now` belongs to.
        """
        user = await UserRepository(db).lock(user_id)
        if user is None:
            raise LookupError("the principal's user is gone")
        current = await current_day(
            db, user_id, now, steps_per_day=self._settings.steps_per_day
        )
        calendar = await self._calendar(db, current.settings, user_id)
        days = DayRepository(db)
        today = current.date
        previous = await days.latest(user_id)

        if previous is None:
            first = calendar.first_habit_date()
            if first is None:
                return Ensured(user, calendar, None)
            day = first
            # A first habit created after its day ended starts the next day.
            created = calendar.first_habit_created_at()
            if created is not None and calendar.window(day).ends_at <= created:
                day += timedelta(days=1)
        else:
            day = previous.date + timedelta(days=1)

        while day <= today:
            if calendar.habits_on(day):
                if previous is not None:
                    await self._settle(db, calendar, previous, now)
                previous = await days.add(
                    self._new_day(user_id, calendar, day, previous)
                )
            day += timedelta(days=1)

        if (
            previous is not None
            and previous.settled_at is None
            and calendar.next_day_starts_at(previous) <= now
        ):
            await self._settle(db, calendar, previous, now)

        current = previous if previous is not None and previous.date == today else None
        return Ensured(user, calendar, current)

    async def record(self, db: AsyncSession, calendar: Calendar, row: Day) -> DayRecord:
        before = await DayRepository(db).before(row.user_id, row.date)
        return DayRecord(
            row=row,
            window=calendar.stored_window(row),
            next_day_starts_at=calendar.next_day_starts_at(row),
            habits=calendar.habits_on(row.date),
            logs=await LogRepository(db).for_day(row.user_id, row.date),
            streak_before=0 if before is None else before.streak_after or 0,
            steps_per_day=self._settings.steps_per_day,
        )

    def _new_day(
        self, user_id: UUID, calendar: Calendar, day: date, previous: Day | None
    ) -> Day:
        if previous is None:
            # The first day starts when the first habit was created, if later.
            not_before = calendar.first_habit_created_at()
            starting_lead = Fraction(self._settings.starting_lead)
        else:
            if previous.date == day - timedelta(days=1):
                not_before = previous.ends_at
            else:
                not_before = calendar.window(day - timedelta(days=1)).ends_at
            assert previous.result is not None and previous.end_lead is not None
            starting_lead = starting_lead_after(
                rules.DayState(previous.result),
                previous.end_lead,
                full_lead=self._settings.starting_lead,
            )
        window = calendar.window(day, not_before=not_before)
        return Day(
            user_id=user_id,
            date=day,
            starts_at=window.starts_at,
            ends_at=window.ends_at,
            starting_lead=starting_lead,
        )

    async def _settle(
        self, db: AsyncSession, calendar: Calendar, row: Day, now: datetime
    ) -> None:
        if row.settled_at is not None:
            return
        record = await self.record(db, calendar, row)
        final = record.final()
        row.result = final.state.value
        row.end_lead = final.lead
        row.caught_at = final.caught_at
        row.streak_after = streak_after(record.streak_before, final.state)
        row.settled_at = now
        await db.flush()

    async def _calendar(
        self, db: AsyncSession, settings_rows: list[DaySettingsRow], user_id: UUID
    ) -> Calendar:
        habits = HabitRepository(db)
        rows = await habits.for_user(user_id)
        return Calendar(
            settings_rows,
            [
                (h, [(t.effective_from, t.target) for t in await habits.targets(h.id)])
                for h in rows
            ],
            steps_per_day=self._settings.steps_per_day,
        )
