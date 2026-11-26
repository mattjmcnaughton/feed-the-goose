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
    lead: float
    as_of: Instant
    steps_per_hour: float
    day_ends_at: Instant
    days: list[ProfileDay] = Field(description="The last 35 days, oldest first.")
