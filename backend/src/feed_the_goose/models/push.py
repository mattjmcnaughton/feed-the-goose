"""Installations, reminder jobs and recorded deliveries (TDD §5.2, §5.9)."""

from datetime import date, datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from feed_the_goose.models.base import Base


class Installation(Base):
    __tablename__ = "installations"
    __table_args__ = (
        UniqueConstraint("user_id", "installation_id"),
        CheckConstraint("environment IN ('sandbox', 'production')", name="environment"),
    )

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    installation_id: Mapped[str]
    # Cleared when APNs answers 410 Unregistered.
    apns_token: Mapped[str | None]
    widget_push_token: Mapped[str | None]
    environment: Mapped[str]
    app_version: Mapped[str]
    created_at: Mapped[datetime]
    updated_at: Mapped[datetime]


class PushJob(Base):
    """A planned reminder. Unique per user, day and kind, so it is sent once."""

    __tablename__ = "push_jobs"
    __table_args__ = (UniqueConstraint("user_id", "date", "kind"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    date: Mapped[date]
    kind: Mapped[str]
    due_at: Mapped[datetime] = mapped_column(index=True)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    sent_at: Mapped[datetime | None]
    attempts: Mapped[int] = mapped_column(default=0)


class PushDelivery(Base):
    """What the recording sender "sent". Development and tests only."""

    __tablename__ = "push_deliveries"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    installation_id: Mapped[str]
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    sent_at: Mapped[datetime]
