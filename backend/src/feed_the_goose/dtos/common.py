"""Types shared by the API's request and response models (TDD §4)."""

from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated

from pydantic import AfterValidator, AwareDatetime, BaseModel, ConfigDict, Field


class Dto(BaseModel):
    """Base for every API model. Unknown fields are refused."""

    model_config = ConfigDict(extra="forbid")


def _to_utc(value: datetime) -> datetime:
    return value.astimezone(UTC)


# An instant with a time zone, sent in UTC such as 2026-11-26T14:05:00Z.
Instant = Annotated[AwareDatetime, AfterValidator(_to_utc)]

# A local time of day such as 06:00, in the user's time zone.
LocalTime = Annotated[str, Field(pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")]


class Pursuer(StrEnum):
    """The pursuers the server supports."""

    goose = "goose"


class ChaseState(StrEnum):
    """The state of a day's chase. A settled day is complete, short or caught."""

    running = "running"
    complete = "complete"
    short = "short"
    caught = "caught"
