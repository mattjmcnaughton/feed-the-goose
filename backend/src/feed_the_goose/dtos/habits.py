"""Habits (API spec "Habits")."""

from datetime import date
from uuid import UUID

from pydantic import Field

from feed_the_goose.dtos.common import Dto


class Habit(Dto):
    """A habit belongs to a day when `effective_from <= day < archived_from`."""

    id: UUID
    name: str
    unit: str
    target: int
    chunk: int = Field(description="The usual amount, logged by one tap.")
    position: int
    effective_from: date
    archived_from: date | None


class HabitCreate(Dto):
    name: str = Field(min_length=1)
    unit: str = Field(min_length=1)
    target: int = Field(gt=0)
    chunk: int = Field(gt=0)


class HabitUpdate(Dto):
    """Fields to change. A new target takes effect from the next day."""

    name: str | None = Field(default=None, min_length=1)
    unit: str | None = Field(default=None, min_length=1)
    target: int | None = Field(default=None, gt=0)
    chunk: int | None = Field(default=None, gt=0)
    position: int | None = Field(default=None, ge=0)
