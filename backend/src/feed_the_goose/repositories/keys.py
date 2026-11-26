"""API and MCP keys, found by their secret's digest (owned by T07 after T04)."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Key


class KeyRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, key: Key) -> Key:
        self._session.add(key)
        await self._session.flush()
        return key

    async def active_by_digest(self, digest: str) -> Key | None:
        return await self._session.scalar(
            select(Key).where(Key.digest == digest, Key.revoked_at.is_(None))
        )

    async def active_for_user(self, user_id: UUID) -> list[Key]:
        rows = await self._session.scalars(
            select(Key)
            .where(Key.user_id == user_id, Key.revoked_at.is_(None))
            .order_by(Key.created_at, Key.id)
        )
        return list(rows)

    async def revoke(self, user_id: UUID, key_id: UUID, now: datetime) -> bool:
        """Revoke the user's key. False when the user has no such active key."""
        revoked = await self._session.scalar(
            update(Key)
            .where(Key.id == key_id, Key.user_id == user_id, Key.revoked_at.is_(None))
            .values(revoked_at=now)
            .returning(Key.id)
        )
        return revoked is not None
