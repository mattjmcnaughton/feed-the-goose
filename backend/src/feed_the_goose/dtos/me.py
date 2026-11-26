"""The signed-in user and their settings (API spec "Me")."""

from datetime import date
from uuid import UUID

from pydantic import Field

from feed_the_goose.dtos.common import Dto, Instant, LocalTime, Pursuer, RequestDto


class PendingDay(Dto):
    """Day settings that take effect when the day `effective_from` starts."""

    effective_from: date
    time_zone: str
    day_start: LocalTime
    day_end: LocalTime


class User(Dto):
    """The signed-in user. The day fields are the ones in effect today."""

    id: UUID
    email: str
    display_name: str
    pursuer: Pursuer
    time_zone: str = Field(description="An IANA time zone, such as America/New_York.")
    day_start: LocalTime
    day_end: LocalTime
    pending: PendingDay | None
    created_at: Instant


class UserUpdate(RequestDto):
    """Fields to change. Changes to the day take effect from the next day."""

    display_name: str | None = Field(default=None, min_length=1)
    pursuer: Pursuer | None = None
    time_zone: str | None = Field(default=None, min_length=1)
    day_start: LocalTime | None = None
    day_end: LocalTime | None = None
