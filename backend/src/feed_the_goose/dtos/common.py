"""Types shared by the API's request and response models (TDD §4)."""

from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated

from pydantic import (
    AfterValidator,
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    PlainSerializer,
    WithJsonSchema,
)


class Dto(BaseModel):
    """Base for response models. Their schemas stay open, so a client already
    installed keeps decoding a response that gains a field."""


class RequestDto(Dto):
    """Base for request models. Unknown fields are refused."""

    model_config = ConfigDict(extra="forbid")


def _to_utc(value: datetime) -> datetime:
    return value.astimezone(UTC)


def _whole_seconds(value: datetime) -> str:
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


# An instant with a time zone. Sent in UTC to the whole second, such as
# 2026-11-26T14:05:00Z, so one ISO 8601 format decodes every timestamp.
Instant = Annotated[
    AwareDatetime,
    AfterValidator(_to_utc),
    PlainSerializer(_whole_seconds, when_used="json"),
    WithJsonSchema({"type": "string", "format": "date-time"}),
]

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
