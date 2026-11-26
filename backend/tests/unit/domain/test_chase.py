"""Chase rules the example table leaves implicit."""

from datetime import date, datetime, time
from fractions import Fraction
from zoneinfo import ZoneInfo

from feed_the_goose.domain.chase import (
    DayState,
    EventKind,
    HabitTarget,
    LogEntry,
    chase_at,
)
from feed_the_goose.domain.day import DaySettings, day_window

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
