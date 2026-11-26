"""The example days of TDD §5.3, one test case per row, named by its number.

Expected values are the table's, worked out by hand. Rule numbers are the TDD's
defaults, written here rather than read from the settings, so the table checks the
rules and not the configuration.

The base day is 2026-11-26 in America/New_York, 06:00 to 00:00 (11:00Z to 05:00Z,
18 hours, pace 5.56), a starting lead of 100, and three habits: Pushups 50, Workout 30,
Reading 20.
"""

from collections.abc import Callable
from datetime import UTC, date, datetime, time, timedelta
from fractions import Fraction
from zoneinfo import ZoneInfo

import pytest

from feed_the_goose.domain.chase import (
    ChaseState,
    DayState,
    EventKind,
    HabitTarget,
    LogEntry,
    chase_at,
)
from feed_the_goose.domain.day import (
    DaySettings,
    DayWindow,
    date_of,
    day_window,
    next_day_window,
)
from feed_the_goose.domain.streak import stage, starting_lead_after, streak_after

STEPS_PER_DAY = 100
FULL_LEAD = 100
STAGE_THRESHOLDS = (3, 7, 14, 30)

NEW_YORK = ZoneInfo("America/New_York")
BASE = DaySettings(time_zone="America/New_York", day_start=time(6), day_end=time(0))
TODAY = date(2026, 11, 26)
HABITS = (
    HabitTarget(habit_id="pushups", target=50),
    HabitTarget(habit_id="workout", target=30),
    HabitTarget(habit_id="reading", target=20),
)


def local(day: int, hour: int, minute: int = 0, month: int = 11) -> datetime:
    """An instant at a local New York time in 2026."""
    return datetime(2026, month, day, hour, minute, tzinfo=NEW_YORK)


def log(log_id: str, habit_id: str, amount: int, logged_at: datetime) -> LogEntry:
    return LogEntry(id=log_id, habit_id=habit_id, amount=amount, logged_at=logged_at)


def window(settings: DaySettings = BASE, **kwargs: datetime) -> DayWindow:
    return day_window(TODAY, settings, steps_per_day=STEPS_PER_DAY, **kwargs)


def chase(
    logs: list[LogEntry],
    at: datetime,
    *,
    starting_lead: int = FULL_LEAD,
    day: DayWindow | None = None,
    habits: tuple[HabitTarget, ...] = HABITS,
) -> ChaseState:
    return chase_at(
        day or window(),
        Fraction(starting_lead),
        habits,
        logs,
        at,
        steps_per_day=STEPS_PER_DAY,
    )


def one(value: Fraction) -> str:
    """Steps as the API shows them: one decimal place."""
    return f"{float(value):.1f}"


def outcome(state: ChaseState, log_id: str) -> tuple[EventKind, str]:
    found = next(o for o in state.outcomes if o.log_id == log_id)
    return found.kind, one(found.steps)


def case_01() -> None:
    day = window()
    assert day.starts_at == datetime(2026, 11, 26, 11, tzinfo=UTC)
    assert day.ends_at == datetime(2026, 11, 27, 5, tzinfo=UTC)
    assert f"{float(day.steps_per_hour):.2f}" == "5.56"

    state = chase([], local(26, 18))

    assert state.state is DayState.RUNNING
    assert one(state.walked) == "66.7"
    assert one(state.lead) == "33.3"
    assert state.caught_at == local(27, 0)


def case_02() -> None:
    logs = [
        log("a", "pushups", 20, local(26, 9)),
        log("b", "workout", 30, local(26, 11)),
    ]

    state = chase(logs, local(26, 18))

    assert state.state is DayState.RUNNING
    assert one(state.earned) == "46.7"
    assert one(state.walked) == "66.7"
    assert one(state.lead) == "80.0"
    assert state.caught_at is None


def case_03() -> None:
    state = chase([log("a", "pushups", 10, local(26, 9))], local(26, 9))

    assert outcome(state, "a") == (EventKind.GAIN, "6.7")


def case_04() -> None:
    logs = [
        log("a", "pushups", 60, local(26, 9)),
        log("b", "pushups", 10, local(26, 10)),
    ]

    state = chase(logs, local(26, 12))

    assert outcome(state, "a") == (EventKind.GAIN, "33.3")
    assert outcome(state, "b") == (EventKind.GAIN, "0.0")


CASE_05_LOGS = [
    log("a", "pushups", 50, local(26, 9)),
    log("b", "workout", 30, local(26, 11)),
    log("c", "reading", 20, local(26, 14)),
]


def case_05() -> None:
    state = chase(CASE_05_LOGS, local(26, 18))

    assert state.state is DayState.COMPLETE
    assert one(state.lead) == "155.6"
    assert outcome(state, "c") == (EventKind.COMPLETE, "33.3")


def case_06() -> None:
    state = chase([], local(26, 12), starting_lead=20)

    assert state.state is DayState.CAUGHT
    assert state.caught_at == local(26, 9, 36)
    assert one(state.lead) == "0.0"
    assert one(state.walked) == "20.0"
    assert one(state.earned) == "0.0"


def case_07() -> None:
    before = chase([], local(26, 12), starting_lead=20)
    assert before.state is DayState.CAUGHT
    assert before.caught_at == local(26, 9, 36)

    late = log("a", "pushups", 50, local(26, 9))
    after = chase([late], local(26, 12), starting_lead=20)

    assert after.state is DayState.RUNNING
    assert one(after.lead) == "20.0"
    assert after.caught_at == local(26, 15, 36)


def case_08() -> None:
    state = chase(
        [log("a", "pushups", 10, local(26, 10))], local(26, 12), starting_lead=20
    )

    assert outcome(state, "a") == (EventKind.CAUGHT, "0.0")
    assert state.state is DayState.CAUGHT
    assert state.caught_at == local(26, 9, 36)


def case_09() -> None:
    state = chase(
        [log("a", "pushups", 10, local(26, 9, 36))], local(26, 10), starting_lead=20
    )

    assert state.state is DayState.RUNNING
    assert state.caught_at == local(26, 10, 48)


CASE_10_LOGS = [log("a", "pushups", 50, local(26, 9))]


def case_10() -> None:
    state = chase(CASE_10_LOGS, local(27, 0))

    assert state.state is DayState.SHORT
    assert one(state.lead) == "33.3"
    tomorrow = starting_lead_after(state.state, state.lead, full_lead=FULL_LEAD)
    assert one(tomorrow) == "33.3"


def case_11() -> None:
    night = local(27, 0, 30)
    assert date_of(night, lambda _: BASE) == TODAY

    state = chase([*CASE_10_LOGS, log("b", "workout", 30, night)], night)

    assert state.state is DayState.SHORT
    assert one(state.lead) == "66.7"
    tomorrow = starting_lead_after(state.state, state.lead, full_lead=FULL_LEAD)
    assert one(tomorrow) == "66.7"


def case_12() -> None:
    night = local(27, 0, 30)
    logs = [
        *CASE_10_LOGS,
        log("b", "workout", 30, night),
        log("c", "reading", 20, night),
    ]

    state = chase(logs, night)

    assert state.state is DayState.COMPLETE
    assert outcome(state, "c")[0] is EventKind.COMPLETE
    assert starting_lead_after(state.state, state.lead, full_lead=FULL_LEAD) == 100


def case_13() -> None:
    state = chase([], local(27, 0))

    assert state.state is DayState.CAUGHT
    assert state.caught_at == local(27, 0)


def case_14() -> None:
    previous_streak = 5
    complete = chase(CASE_05_LOGS, local(26, 18))
    assert streak_after(previous_streak, complete.state) == 6

    undone = chase(CASE_05_LOGS[:2], local(26, 18))

    assert undone.state is DayState.RUNNING
    assert one(undone.lead) == "100.0"
    assert streak_after(previous_streak, undone.state) == 5


def case_15() -> None:
    late = DaySettings(
        time_zone="America/New_York", day_start=time(10), day_end=time(2)
    )

    day = window(late)

    assert day.ends_at == local(27, 2)
    assert f"{float(day.steps_per_hour):.2f}" == "6.25"
    assert date_of(local(27, 1, 30), lambda _: late) == TODAY


def case_16() -> None:
    long = DaySettings(time_zone="America/New_York", day_start=time(6), day_end=time(2))

    day = day_window(date(2026, 10, 31), long, steps_per_day=STEPS_PER_DAY)

    assert day.ends_at - day.starts_at == timedelta(hours=21)
    assert f"{float(day.steps_per_hour):.2f}" == "4.76"
    state = chase([], day.ends_at, day=day)
    assert state.walked == 100


def case_17() -> None:
    pacific = DaySettings(
        time_zone="America/Los_Angeles", day_start=time(6), day_end=time(0)
    )

    def settings_for(day: date) -> DaySettings:
        return BASE if day <= TODAY else pacific

    today = day_window(TODAY, settings_for(TODAY), steps_per_day=STEPS_PER_DAY)
    assert today == window()

    tomorrow = next_day_window(
        today, settings_for(TODAY + timedelta(days=1)), steps_per_day=STEPS_PER_DAY
    )
    pacific_six = datetime(2026, 11, 27, 6, tzinfo=ZoneInfo("America/Los_Angeles"))
    assert tomorrow.starts_at == pacific_six
    assert date_of(pacific_six - timedelta(minutes=1), settings_for) == TODAY
    assert date_of(pacific_six, settings_for) == TODAY + timedelta(days=1)


def case_18() -> None:
    day = window(not_before=local(26, 20))
    assert day.starts_at == local(26, 20)

    state = chase([], local(27, 0), day=day)

    assert one(state.walked) == "22.2"
    assert state.state is DayState.SHORT
    assert one(state.lead) == "77.8"


def case_19() -> None:
    pushups = [log("a", "pushups", 20, local(26, 11))]

    today = chase(pushups, local(26, 12))
    tomorrow_habits = (HabitTarget(habit_id="pushups", target=100), *HABITS[1:])
    tomorrow = chase(pushups, local(26, 12), habits=tomorrow_habits)

    assert outcome(today, "a") == (EventKind.GAIN, "13.3")
    assert outcome(tomorrow, "a") == (EventKind.GAIN, "6.7")


def case_20() -> None:
    streaks = [0, 2, 3, 6, 7, 13, 14, 29, 30]

    stages = [stage(s, STAGE_THRESHOLDS) for s in streaks]

    assert stages == [0, 0, 1, 1, 2, 2, 3, 3, 4]


def case_21() -> None:
    results = [
        DayState.COMPLETE,
        DayState.SHORT,
        DayState.COMPLETE,
        DayState.CAUGHT,
        DayState.COMPLETE,
    ]

    streaks = []
    streak = 0
    for result in results:
        streak = streak_after(streak, result)
        streaks.append(streak)

    assert streaks == [1, 1, 2, 0, 1]


CASES: list[Callable[[], None]] = [
    case_01,
    case_02,
    case_03,
    case_04,
    case_05,
    case_06,
    case_07,
    case_08,
    case_09,
    case_10,
    case_11,
    case_12,
    case_13,
    case_14,
    case_15,
    case_16,
    case_17,
    case_18,
    case_19,
    case_20,
    case_21,
]


@pytest.mark.parametrize(
    "case", CASES, ids=[f"case_{n:02}" for n in range(1, len(CASES) + 1)]
)
def test_example_day(case: Callable[[], None]) -> None:
    case()
