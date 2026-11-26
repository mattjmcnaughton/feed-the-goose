"""The public profile and its settings (API spec "Public profile").

`PublicProfile` is the published projection: never habit names, units, amounts, log
times or the user's day hours (constitution §5).
"""

import datetime as dt
from typing import Annotated

from pydantic import Field

from feed_the_goose.dtos.common import ChaseState, Dto, Instant, Pursuer, RequestDto

Handle = Annotated[str, Field(pattern=r"^[a-z0-9-]{3,30}$")]


class ProfileSettings(Dto):
    handle: str | None
    public: bool


class ProfileUpdate(RequestDto):
    handle: Handle
    public: bool


class ProfileDay(Dto):
    date: dt.date
    result: ChaseState


class PublicProfile(Dto):
    display_name: str
    pursuer: Pursuer
    complete_days: int
    stage: int
    state: ChaseState
    lead: float = Field(description="Exact at `as_of`.")
    as_of: Instant
    steps_per_hour: float
    caught_at: Instant | None = Field(
        description=(
            "When the lead reaches 0 if nothing more is logged, or when the catch "
            "happened. Null when no catch happens before the day ends. The day's "
            "hours are never published, so a client counting the lead down stops "
            "at this time and otherwise shows the lead as of `as_of`."
        )
    )
    days: list[ProfileDay] = Field(description="The last 35 days, oldest first.")
