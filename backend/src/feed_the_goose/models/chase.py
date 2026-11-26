"""Days and logs, the records a chase is computed from (TDD §5.2, §5.4, §5.5)."""

from datetime import date, datetime
from fractions import Fraction
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, ForeignKey, Index, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from feed_the_goose.models.base import Base, ExactFraction


class Day(Base):
    """One day of a user's chase. The window is stored when the row is created, so
    later setting changes cannot move it. The result columns are set once, when the
    day settles."""

    __tablename__ = "days"
    __table_args__ = (
        UniqueConstraint("user_id", "date"),
        CheckConstraint(
            "result IS NULL OR result IN ('complete', 'short', 'caught')",
            name="result_settled",
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    date: Mapped[date]
    starts_at: Mapped[datetime]
    ends_at: Mapped[datetime]
    starting_lead: Mapped[Fraction] = mapped_column(ExactFraction)
    result: Mapped[str | None]
    end_lead: Mapped[Fraction | None] = mapped_column(ExactFraction)
    caught_at: Mapped[datetime | None]
    streak_after: Mapped[int | None]
    settled_at: Mapped[datetime | None]


class Log(Base):
    """The client's ID is the primary key, so a retry cannot add a second row. An
    undone log stays as a tombstone with `undone_at` set."""

    __tablename__ = "logs"
    __table_args__ = (
        Index(None, "user_id", "date"),
        CheckConstraint("amount > 0", name="amount_positive"),
        CheckConstraint(
            "source IN ('app', 'widget', 'shortcuts', 'api', 'mcp')", name="source"
        ),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    habit_id: Mapped[UUID] = mapped_column(ForeignKey("habits.id", ondelete="CASCADE"))
    amount: Mapped[int]
    logged_at: Mapped[datetime]
    received_at: Mapped[datetime]
    source: Mapped[str]
    # The day the log belongs to, from `logged_at`.
    date: Mapped[date]
    undone_at: Mapped[datetime | None]
