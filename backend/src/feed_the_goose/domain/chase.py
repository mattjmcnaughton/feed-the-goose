"""The chase: the state of one day at an instant, and what each log did.

TDD §5.3. Pure: the window, the starting lead, the habits, the logs and the instant
are all arguments. Arithmetic is exact; rounding belongs to whoever builds a DTO.
"""

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from fractions import Fraction
from itertools import groupby

from feed_the_goose.domain.day import DayWindow, hours_between


class DayState(StrEnum):
    RUNNING = "running"
    COMPLETE = "complete"
    SHORT = "short"
    CAUGHT = "caught"


class EventKind(StrEnum):
    GAIN = "gain"
    COMPLETE = "complete"
    CAUGHT = "caught"


@dataclass(frozen=True)
class HabitTarget:
    """A habit of the day and the target that applies to that day."""

    habit_id: str
    target: int


@dataclass(frozen=True)
class LogEntry:
    """A log that is not undone."""

    id: str
    habit_id: str
    amount: int
    logged_at: datetime


@dataclass(frozen=True)
class LogOutcome:
    """What one log did: its event and the steps it earned."""

    log_id: str
    kind: EventKind
    steps: Fraction


@dataclass(frozen=True)
class HabitProgress:
    habit_id: str
    target: int
    logged: int
    steps: Fraction
    done: bool


@dataclass(frozen=True)
class ChaseState:
    """The day at `at`.

    `caught_at` is the catch for a caught day, the projected catch for a running day
    (null when that falls after the day's end), and null otherwise. `completed_at` is
    set for a complete day. `outcomes` covers every log at or before `at`, in the
    order applied.
    """

    state: DayState
    at: datetime
    lead: Fraction
    earned: Fraction
    walked: Fraction
    caught_at: datetime | None
    completed_at: datetime | None
    habits: tuple[HabitProgress, ...]
    outcomes: tuple[LogOutcome, ...]


def chase_at(
    day: DayWindow,
    starting_lead: Fraction,
    habits: Iterable[HabitTarget],
    logs: Iterable[LogEntry],
    at: datetime,
    *,
    steps_per_day: int,
) -> ChaseState:
    """Work out the chase of `day` at `at` from the logs made by then.

    Logs apply in order of `logged_at`, then of ID. Logs at the instant of a catch
    apply first. Logs after a catch or after completion earn nothing. Logs during the
    night may raise the lead or complete the day, but cannot undo an earlier catch.
    """
    at = at.astimezone(UTC)
    habits = tuple(habits)
    share = Fraction(steps_per_day, len(habits))
    targets = {h.habit_id: h.target for h in habits}
    logged = dict.fromkeys(targets, 0)
    steps = dict.fromkeys(targets, Fraction(0))
    total_hours = hours_between(day.starts_at, day.ends_at)

    def hours_at(instant: datetime) -> Fraction:
        return min(max(hours_between(day.starts_at, instant), Fraction(0)), total_hours)

    def walked_at(hours: Fraction) -> Fraction:
        return day.steps_per_hour * hours

    def catch_hours(earned: Fraction) -> Fraction | None:
        """Hours until the lead reaches 0 with no more logs, if by the day's end."""
        hours = (starting_lead + earned) / day.steps_per_hour
        return hours if hours <= total_hours else None

    earned = Fraction(0)
    caught: Fraction | None = None
    completed: Fraction | None = None
    completed_at: datetime | None = None
    outcomes: list[LogOutcome] = []

    ordered = sorted(
        (log for log in logs if log.logged_at.astimezone(UTC) <= at),
        key=lambda log: (log.logged_at.astimezone(UTC), log.id),
    )
    for instant, group in groupby(
        ordered, key=lambda log: log.logged_at.astimezone(UTC)
    ):
        hours = hours_at(instant)
        if caught is None and completed is None:
            projected = catch_hours(earned)
            # Real time, so a catch at the day's end comes before night logs.
            if projected is not None and projected < hours_between(
                day.starts_at, instant
            ):
                caught = projected
        applied: list[LogOutcome] = []
        for log in group:
            logged[log.habit_id] += log.amount
            if caught is not None:
                outcomes.append(LogOutcome(log.id, EventKind.CAUGHT, Fraction(0)))
                continue
            if completed is not None:
                applied.append(LogOutcome(log.id, EventKind.GAIN, Fraction(0)))
                continue
            gained = min(
                share * log.amount / targets[log.habit_id], share - steps[log.habit_id]
            )
            steps[log.habit_id] += gained
            earned += gained
            if all(s == share for s in steps.values()):
                completed, completed_at = hours, instant
                applied.append(LogOutcome(log.id, EventKind.COMPLETE, gained))
            else:
                applied.append(LogOutcome(log.id, EventKind.GAIN, gained))
        if (
            completed is None
            and caught is None
            and starting_lead + earned - walked_at(hours) <= 0
        ):
            # These logs did not lift the lead above 0, so they are part of the catch.
            caught = hours
            applied = [
                LogOutcome(o.log_id, EventKind.CAUGHT, Fraction(0)) for o in applied
            ]
        outcomes.extend(applied)

    projected = None
    if caught is None and completed is None:
        projected = catch_hours(earned)
        if projected is not None and projected <= hours_at(at):
            caught, projected = projected, None

    if caught is not None:
        state, stop = DayState.CAUGHT, caught
    elif completed is not None:
        state, stop = DayState.COMPLETE, completed
    elif at >= day.ends_at:
        state, stop = DayState.SHORT, total_hours
    else:
        state, stop = DayState.RUNNING, hours_at(at)

    walked = walked_at(stop)
    lead = max(starting_lead + earned - walked, Fraction(0))
    catch = caught if caught is not None else projected

    return ChaseState(
        state=state,
        at=at,
        lead=lead,
        earned=earned,
        walked=walked,
        caught_at=None if catch is None else _instant(day, catch),
        completed_at=completed_at,
        habits=tuple(
            HabitProgress(
                habit_id=h.habit_id,
                target=h.target,
                logged=logged[h.habit_id],
                steps=steps[h.habit_id],
                done=steps[h.habit_id] == share,
            )
            for h in habits
        ),
        outcomes=tuple(outcomes),
    )


def _instant(day: DayWindow, hours: Fraction) -> datetime:
    """The instant `hours` into the day, to the nearest microsecond."""
    return day.starts_at + timedelta(microseconds=round(hours * 3_600_000_000))
