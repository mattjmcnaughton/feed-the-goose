"""The day's chase, events and history (API spec "Objects", "Chase and history").

Steps are rounded to one decimal place and `steps_per_hour` to two, only here.
"""

import datetime as dt
from enum import StrEnum
from uuid import UUID

from pydantic import Field

from feed_the_goose.dtos.common import ChaseState, Dto, Instant, Pursuer


class ChaseHabit(Dto):
    """One habit's progress in a day, in `position` order."""

    habit_id: UUID
    name: str
    unit: str
    target: int
    chunk: int
    logged: int
    steps: float
    done: bool


class Streak(Dto):
    complete_days: int = Field(description="Includes today when today is complete.")
    stage: int = Field(ge=0)


class Chase(Dto):
    """The state of a day's chase at `as_of`."""

    date: dt.date
    pursuer: Pursuer
    state: ChaseState
    as_of: Instant
    lead: float = Field(description="Exact at `as_of`.")
    starting_lead: float
    earned: float
    walked: float
    steps_per_hour: float
    day_starts_at: Instant
    day_ends_at: Instant
    next_day_starts_at: Instant = Field(
        description="When this day settles and the next begins."
    )
    caught_at: Instant | None = Field(
        description=(
            "When the lead reaches 0 if nothing more is logged, or when the catch "
            "happened. Null when no catch happens by `day_ends_at`."
        )
    )
    habits: list[ChaseHabit]
    streak: Streak


class EventKind(StrEnum):
    gain = "gain"
    complete = "complete"
    caught = "caught"
    undone = "undone"


class Event(Dto):
    """What a log or an undo did, so the app knows which clip to play."""

    kind: EventKind
    habit_id: UUID
    steps: float = Field(
        description="What the log earned; for `undone`, what it had earned."
    )


class DaySummary(Dto):
    """One day's result. `end_lead` is null while the day is running."""

    date: dt.date
    pursuer: Pursuer
    result: ChaseState
    end_lead: float | None
    complete_days: int = Field(description="The streak after this day.")
