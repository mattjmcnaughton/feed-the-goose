"""Plan a day's reminders from its chase (TDD §5.9, PRD S14).

Pure: the window, the chase, the preferences and the lead time are all arguments.
Only a running day gets reminders, at most three:

- when the lead would fall below the user's threshold;
- `remind_before` ahead of the projected catch;
- `remind_before` ahead of the day's end.

Each assumes no more logs, so a log moves them. One that falls in quiet hours or
before the chase's instant is dropped. A day-end reminder due at the same instant
as another is dropped too, so that a catch at the day's end sends one, not two.
"""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from enum import StrEnum
from fractions import Fraction
from typing import Any
from zoneinfo import ZoneInfo

from feed_the_goose.domain.chase import ChaseState, DayState
from feed_the_goose.domain.day import MICROSECONDS_PER_HOUR, DayWindow


class ReminderKind(StrEnum):
    LEAD_LOW = "lead_low"
    BEFORE_CAUGHT = "before_caught"
    BEFORE_DAY_END = "before_day_end"


@dataclass(frozen=True)
class Preferences:
    """The user's reminder preferences. Quiet hours are local times in
    `time_zone`, start included and end excluded; the end may be the next date."""

    when_lead_below: int
    quiet_hours: tuple[time, time] | None
    time_zone: str


@dataclass(frozen=True)
class Reminder:
    kind: ReminderKind
    due_at: datetime


def plan(
    window: DayWindow,
    chase: ChaseState,
    preferences: Preferences,
    *,
    remind_before: timedelta,
) -> list[Reminder]:
    """The reminders still to come for the day of `chase`, in order of due time."""
    if chase.state is not DayState.RUNNING:
        return []
    planned: list[Reminder] = []

    if preferences.when_lead_below > 0:
        # The pursuer walks until the day ends; with no more logs the lead falls
        # at the pace until then.
        hours = (chase.lead - preferences.when_lead_below) / window.steps_per_hour
        falls_below = chase.at + _span(hours)
        if falls_below < window.ends_at:
            planned.append(Reminder(ReminderKind.LEAD_LOW, falls_below))
    if chase.caught_at is not None:
        planned.append(
            Reminder(ReminderKind.BEFORE_CAUGHT, chase.caught_at - remind_before)
        )
    day_end = window.ends_at - remind_before
    if all(r.due_at != day_end for r in planned):
        planned.append(Reminder(ReminderKind.BEFORE_DAY_END, day_end))

    zone = ZoneInfo(preferences.time_zone)
    return sorted(
        (
            r
            for r in planned
            if r.due_at >= chase.at
            and not _quiet(r.due_at.astimezone(zone).time(), preferences.quiet_hours)
        ),
        key=lambda r: r.due_at,
    )


def payload(
    kind: ReminderKind,
    day: date,
    *,
    when_lead_below: int,
    remind_before: timedelta,
) -> dict[str, Any]:
    """The APNs payload of a reminder. The app may replace the words with the
    pursuer's own; `kind` and `date` tell it which reminder this is."""
    ahead = _words(remind_before)
    title, body = {
        ReminderKind.LEAD_LOW: (
            "Your lead is low",
            f"Your lead is below {when_lead_below} steps. Log a habit to get ahead.",
        ),
        ReminderKind.BEFORE_CAUGHT: (
            f"You'll be caught in {ahead}",
            "Log a habit to stay ahead.",
        ),
        ReminderKind.BEFORE_DAY_END: (
            f"Your day ends in {ahead}",
            "Finish your habits to complete the day.",
        ),
    }[kind]
    return {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
            "thread-id": "reminders",
        },
        "kind": kind.value,
        "date": day.isoformat(),
    }


def _words(span: timedelta) -> str:
    """A lead time in words, such as "an hour", "2 hours" or "90 minutes"."""
    seconds = int(span.total_seconds())
    for size, one, many in ((3600, "an hour", "hours"), (60, "a minute", "minutes")):
        if seconds % size == 0:
            count = seconds // size
            return one if count == 1 else f"{count} {many}"
    return "a second" if seconds == 1 else f"{seconds} seconds"


def _span(hours: Fraction) -> timedelta:
    return timedelta(microseconds=int(hours * MICROSECONDS_PER_HOUR))


def _quiet(at: time, quiet_hours: tuple[time, time] | None) -> bool:
    if quiet_hours is None:
        return False
    start, end = quiet_hours
    if start <= end:
        return start <= at < end
    return at >= start or at < end
