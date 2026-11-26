"""The reminder planner (TDD §5.9, PRD S14).

The day is the TDD §5.3 example: 2026-11-26 in America/New_York, 06:00 to 00:00
(11:00Z to 05:00Z), 18 hours, so the pursuer walks 100/18 = 5.56 steps an hour.
Reminders come an hour early and the lead threshold is 30. Every expected time is
worked out by hand below, in local time.
"""

from datetime import UTC, date, datetime, time, timedelta
from fractions import Fraction
from zoneinfo import ZoneInfo

import pytest

from feed_the_goose.domain.chase import HabitTarget, LogEntry, chase_at
from feed_the_goose.domain.day import DaySettings, day_window
from feed_the_goose.push.planner import Preferences, ReminderKind, plan

NEW_YORK = ZoneInfo("America/New_York")
DAY = day_window(
    date(2026, 11, 26),
    DaySettings("America/New_York", time(6), time(0)),
    steps_per_day=100,
)
HABITS = [HabitTarget("pushups", 50), HabitTarget("reading", 20)]


def local(hour: int, minute: int = 0, *, day: int = 26) -> datetime:
    return datetime(2026, 11, day, hour, minute, tzinfo=NEW_YORK).astimezone(UTC)


LEAD_LOW = ReminderKind.LEAD_LOW
BEFORE_CAUGHT = ReminderKind.BEFORE_CAUGHT
BEFORE_DAY_END = ReminderKind.BEFORE_DAY_END

CASES = [
    pytest.param(
        # Starting lead 80, nothing logged, planned at 09:00 (lead 63.3).
        # The lead reaches 30 after (80 - 30) / 5.56 = 9 hours: 15:00.
        # It reaches 0 after 80 / 5.56 = 14.4 hours: 20:24, so 19:24.
        # The day ends at 00:00, so 23:00.
        80,
        [],
        local(9),
        None,
        [
            (LEAD_LOW, local(15)),
            (BEFORE_CAUGHT, local(19, 24)),
            (BEFORE_DAY_END, local(23)),
        ],
        id="plain day: all three",
    ),
    pytest.param(
        # Both habits finished by 10:00: complete, so nothing is due.
        80,
        [("pushups", 50, local(9)), ("reading", 20, local(10))],
        local(11),
        None,
        [],
        id="complete day: none",
    ),
    pytest.param(
        # The plain day with quiet hours 22:00 to 07:00 drops the 23:00 one.
        80,
        [],
        local(9),
        (time(22), time(7)),
        [(LEAD_LOW, local(15)), (BEFORE_CAUGHT, local(19, 24))],
        id="quiet hours across midnight drop the day-end reminder",
    ),
    pytest.param(
        # Quiet hours 19:00 to 20:00 drop 19:24 and keep 15:00 and 23:00.
        80,
        [],
        local(9),
        (time(19), time(20)),
        [(LEAD_LOW, local(15)), (BEFORE_DAY_END, local(23))],
        id="quiet hours in the evening drop the catch reminder",
    ),
    pytest.param(
        # Quiet hours 15:00 to 19:24: a reminder at the start is quiet, one at the
        # end is not.
        80,
        [],
        local(9),
        (time(15), time(19, 24)),
        [(BEFORE_CAUGHT, local(19, 24)), (BEFORE_DAY_END, local(23))],
        id="quiet hours include their start and exclude their end",
    ),
    pytest.param(
        # Starting lead 80, planned at 17:00: walked 61.1, lead 18.9. The lead went
        # below 30 at 15:00, which is past, so that one is dropped.
        80,
        [],
        local(17),
        None,
        [(BEFORE_CAUGHT, local(19, 24)), (BEFORE_DAY_END, local(23))],
        id="a due time in the past is dropped",
    ),
    pytest.param(
        # Starting lead 100, nothing logged, at 10:00 (lead 77.8). The lead reaches
        # 30 after 70 / 5.56 = 12.6 hours: 18:36. It reaches 0 exactly at the
        # day's end, so the catch and the day-end reminders would both be due at
        # 23:00; only one is sent.
        100,
        [],
        local(10),
        None,
        [(LEAD_LOW, local(18, 36)), (BEFORE_CAUGHT, local(23))],
        id="a catch at the day's end gives one reminder at 23:00",
    ),
    pytest.param(
        # The spec's example: Pushups 20 and Reading 20 by noon, at 18:00. Earned
        # 20 + 50 = 70, walked 66.7, lead 103.3. Six hours walk 33.3 more, so the
        # lead never reaches 30 and there is no catch: only the day-end reminder.
        100,
        [("pushups", 20, local(11)), ("reading", 20, local(12))],
        local(18),
        None,
        [(BEFORE_DAY_END, local(23))],
        id="well ahead: only the day-end reminder",
    ),
    pytest.param(
        # Starting lead 20 is caught at 20 / 5.56 = 3.6 hours: 09:36.
        20,
        [],
        local(12),
        None,
        [],
        id="caught day: none",
    ),
    pytest.param(
        # Pushups only, at 00:30 on the next date: the day is short.
        100,
        [("pushups", 50, local(9))],
        local(0, 30, day=27),
        None,
        [],
        id="short day at night: none",
    ),
]


@pytest.mark.parametrize(("lead", "logs", "at", "quiet", "expected"), CASES)
def test_plan(lead, logs, at, quiet, expected):
    entries = [
        LogEntry(f"log-{n}", habit, amount, logged_at)
        for n, (habit, amount, logged_at) in enumerate(logs)
    ]
    chase = chase_at(DAY, Fraction(lead), HABITS, entries, at, steps_per_day=100)
    preferences = Preferences(
        when_lead_below=30, quiet_hours=quiet, time_zone="America/New_York"
    )

    planned = plan(DAY, chase, preferences, remind_before=timedelta(hours=1))

    assert [(r.kind, r.due_at) for r in planned] == expected
