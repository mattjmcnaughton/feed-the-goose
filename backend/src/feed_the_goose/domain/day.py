"""The day window: when a day starts and ends, and how fast the pursuer walks.

TDD §5.3. Pure: every rule number and instant is an argument.
"""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from fractions import Fraction
from zoneinfo import ZoneInfo

MICROSECONDS_PER_HOUR = 3_600_000_000


@dataclass(frozen=True)
class DaySettings:
    """The user's day start, day end and time zone that apply to a date."""

    time_zone: str
    day_start: time
    day_end: time


@dataclass(frozen=True)
class DayWindow:
    """One day's window, in UTC, and the pursuer's pace over it."""

    date: date
    starts_at: datetime
    ends_at: datetime
    steps_per_hour: Fraction


def hours_between(start: datetime, end: datetime) -> Fraction:
    """Real hours from `start` to `end`, exactly."""
    return _hours(end - start)


def nominal_day_hours(day_start: time, day_end: time) -> Fraction:
    """The local length of a day. An end at or before the start is tomorrow."""
    start = timedelta(hours=day_start.hour, minutes=day_start.minute)
    end = timedelta(hours=day_end.hour, minutes=day_end.minute)
    if end <= start:
        end += timedelta(days=1)
    return _hours(end - start)


def day_length_is_valid(
    day_start: time, day_end: time, *, min_hours: int, max_hours: int
) -> bool:
    """Whether the local length is within the allowed hours, both ends included."""
    return min_hours <= nominal_day_hours(day_start, day_end) <= max_hours


def day_window(
    day: date,
    settings: DaySettings,
    *,
    steps_per_day: int,
    not_before: datetime | None = None,
) -> DayWindow:
    """The window of `day` under `settings`.

    `starts_at` is the day start on that date and `ends_at` the next day end after it.
    The pace spreads `steps_per_day` over the real hours between them, so a day across
    a clock change still totals `steps_per_day`.

    `not_before` moves the start later without changing the pace, so the pursuer walks
    fewer steps: a user's first day starts when the first habit is created, and a day
    never starts before the previous one ends.
    """
    scheduled_start, ends_at = _scheduled(day, settings)
    pace = steps_per_day / hours_between(scheduled_start, ends_at)
    starts_at = scheduled_start
    if not_before is not None:
        # A start past the scheduled end leaves a day with no time in it.
        starts_at = max(starts_at, not_before.astimezone(UTC))
        ends_at = max(ends_at, starts_at)
    return DayWindow(
        date=day, starts_at=starts_at, ends_at=ends_at, steps_per_hour=pace
    )


def next_day_window(
    previous: DayWindow, settings: DaySettings, *, steps_per_day: int
) -> DayWindow:
    """The window of the date after `previous`, never starting before it ends."""
    return day_window(
        previous.date + timedelta(days=1),
        settings,
        steps_per_day=steps_per_day,
        not_before=previous.ends_at,
    )


def date_of(instant: datetime, settings_for: Callable[[date], DaySettings]) -> date:
    """The date of the day an instant belongs to.

    That is the latest date whose day has started by `instant`. An instant during the
    night belongs to the day that just ended. `settings_for` gives the settings in
    effect on a date.
    """
    instant = instant.astimezone(UTC)
    utc_date = instant.date()
    # A day's start lies within about a day and a half of its UTC date, in any zone.
    for day in (utc_date + timedelta(days=n) for n in (1, 0, -1, -2)):
        previous = day - timedelta(days=1)
        _, previous_ends_at = _scheduled(previous, settings_for(previous))
        starts_at, _ = _scheduled(day, settings_for(day))
        if max(starts_at, previous_ends_at) <= instant:
            return day
    raise ValueError("no day has started by this instant")


def _hours(span: timedelta) -> Fraction:
    return Fraction(span // timedelta(microseconds=1), MICROSECONDS_PER_HOUR)


def _scheduled(day: date, settings: DaySettings) -> tuple[datetime, datetime]:
    """The day's start and end before any `not_before`, in UTC."""
    zone = ZoneInfo(settings.time_zone)
    start = datetime.combine(day, settings.day_start, tzinfo=zone)
    end = datetime.combine(day, settings.day_end, tzinfo=zone)
    if settings.day_end <= settings.day_start:
        end = datetime.combine(day + timedelta(days=1), settings.day_end, tzinfo=zone)
    return start.astimezone(UTC), end.astimezone(UTC)
