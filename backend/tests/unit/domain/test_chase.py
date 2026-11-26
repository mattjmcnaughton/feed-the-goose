"""Chase rules the example table leaves implicit."""

from datetime import UTC, date, datetime, time
from fractions import Fraction
from zoneinfo import ZoneInfo

import pytest

from feed_the_goose.domain.chase import (
    DayState,
    EventKind,
    HabitTarget,
    LogEntry,
    chase_at,
)
from feed_the_goose.domain.day import (
    DaySettings,
    day_length_is_valid,
    day_window,
    next_day_window,
)

NEW_YORK = ZoneInfo("America/New_York")


def test_a_night_log_cannot_undo_a_catch_at_the_end_of_the_day() -> None:
    settings = DaySettings(
        time_zone="America/New_York", day_start=time(6), day_end=time(0)
    )
    day = day_window(date(2026, 11, 26), settings, steps_per_day=100)
    night = datetime(2026, 11, 27, 0, 30, tzinfo=NEW_YORK)
    late = LogEntry(id="a", habit_id="pushups", amount=50, logged_at=night)

    state = chase_at(
        day,
        Fraction(100),
        [HabitTarget("pushups", 50), HabitTarget("workout", 30)],
        [late],
        night,
        steps_per_day=100,
    )

    assert state.state is DayState.CAUGHT
    assert state.caught_at == datetime(2026, 11, 27, 0, tzinfo=NEW_YORK)
    assert [(o.kind, o.steps) for o in state.outcomes] == [(EventKind.CAUGHT, 0)]


def test_a_day_never_starts_before_the_previous_one_ends() -> None:
    new_york = DaySettings(
        time_zone="America/New_York", day_start=time(6), day_end=time(2)
    )
    tokyo = DaySettings(time_zone="Asia/Tokyo", day_start=time(6), day_end=time(14))
    today = day_window(date(2026, 11, 26), new_york, steps_per_day=100)

    tomorrow = next_day_window(today, tokyo, steps_per_day=100)

    assert today.ends_at == datetime(2026, 11, 27, 7, tzinfo=UTC)
    assert tomorrow.starts_at == today.ends_at
    assert tomorrow.ends_at >= tomorrow.starts_at


@pytest.mark.parametrize(
    ("start", "end", "valid"),
    [
        (time(6), time(14), True),
        (time(6), time(4), True),
        (time(6), time(13, 59), False),
        (time(6), time(5), False),
        (time(6), time(6), False),
    ],
)
def test_a_day_lasts_8_to_22_hours(start: time, end: time, valid: bool) -> None:
    assert day_length_is_valid(start, end, min_hours=8, max_hours=22) is valid
