"""App sessions and keys. Only a secret's SHA-256 digest is stored (constitution §6)."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from feed_the_goose.models.base import Base


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_digest: Mapped[str] = mapped_column(unique=True)
    device_name: Mapped[str]
    created_at: Mapped[datetime]
    last_used_at: Mapped[datetime]
    expires_at: Mapped[datetime]


class Key(Base):
    __tablename__ = "keys"
    __table_args__ = (CheckConstraint("kind IN ('api', 'mcp')", name="kind"),)

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str]
    name: Mapped[str]
    digest: Mapped[str] = mapped_column(unique=True)
    created_at: Mapped[datetime]
    last_used_at: Mapped[datetime | None]
    revoked_at: Mapped[datetime | None]
