"""Logs (API spec "Logs")."""

import datetime as dt
from enum import StrEnum
from uuid import UUID

from pydantic import Field

from feed_the_goose.dtos.chase import Chase, Event
from feed_the_goose.dtos.common import Dto, Instant, RequestDto


class Source(StrEnum):
    """The surface a log came from."""

    app = "app"
    widget = "widget"
    shortcuts = "shortcuts"
    api = "api"
    mcp = "mcp"


class LogCreate(RequestDto):
    """A log. The client creates `id` (a UUIDv7) and `logged_at` once."""

    id: UUID
    habit_id: UUID
    amount: int | None = Field(
        default=None, gt=0, description="Defaults to the habit's chunk."
    )
    logged_at: Instant
    source: Source


class Log(Dto):
    id: UUID
    habit_id: UUID
    amount: int
    logged_at: Instant
    source: Source
    date: dt.date = Field(description="The day the log belongs to.")
    steps: float = Field(description="What the log counts for now; 0 once undone.")
    undone_at: Instant | None


class LogResult(Dto):
    """A log, what it did, and the chase after it."""

    log: Log
    event: Event
    chase: Chase
