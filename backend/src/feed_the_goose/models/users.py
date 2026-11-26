"""Users and their day settings (TDD §5.2)."""

from datetime import date, datetime, time
from uuid import UUID, uuid4

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from feed_the_goose.models.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    # The verified subject from the identity provider, such as `auth0|abc`.
    identity_subject: Mapped[str] = mapped_column(unique=True)
    email: Mapped[str]
    display_name: Mapped[str]
    pursuer: Mapped[str]
    handle: Mapped[str | None] = mapped_column(unique=True)
    public: Mapped[bool] = mapped_column(default=False)
    reminders_enabled: Mapped[bool] = mapped_column(default=False)
    reminder_lead_below: Mapped[int]
    quiet_hours_start: Mapped[time | None]
    quiet_hours_end: Mapped[time | None]
    # Set by every write that changes a chase; the worker compares the two.
    chase_changed_at: Mapped[datetime | None]
    reminders_planned_at: Mapped[datetime | None]
    created_at: Mapped[datetime]


class DaySettings(Base):
    """Append-only. The row with the latest `effective_from` on or before a date
    applies to that date."""

    __tablename__ = "day_settings"
    __table_args__ = (UniqueConstraint("user_id", "effective_from"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    effective_from: Mapped[date]
    time_zone: Mapped[str]
    day_start: Mapped[time]
    day_end: Mapped[time]
    created_at: Mapped[datetime]
