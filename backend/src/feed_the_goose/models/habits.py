"""Habits and their targets (TDD §5.2)."""

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from feed_the_goose.models.base import Base


class Habit(Base):
    """A habit belongs to a date when `effective_from <= date < archived_from`."""

    __tablename__ = "habits"
    __table_args__ = (CheckConstraint("chunk > 0", name="chunk_positive"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str]
    unit: Mapped[str]
    chunk: Mapped[int]
    position: Mapped[int]
    effective_from: Mapped[date]
    archived_from: Mapped[date | None]
    created_at: Mapped[datetime]


class HabitTarget(Base):
    """Append-only, so a settled day's shares can always be recomputed."""

    __tablename__ = "habit_targets"
    __table_args__ = (
        UniqueConstraint("habit_id", "effective_from"),
        CheckConstraint("target > 0", name="target_positive"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    habit_id: Mapped[UUID] = mapped_column(ForeignKey("habits.id", ondelete="CASCADE"))
    effective_from: Mapped[date]
    target: Mapped[int]
