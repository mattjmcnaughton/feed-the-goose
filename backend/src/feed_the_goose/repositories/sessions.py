"""App sessions, found by their token's digest."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Session


class SessionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, row: Session) -> Session:
        self._session.add(row)
        await self._session.flush()
        return row

    async def active_by_digest(self, digest: str, now: datetime) -> Session | None:
        return await self._session.scalar(
            select(Session).where(
                Session.token_digest == digest, Session.expires_at > now
            )
        )

    async def active_for_user(self, user_id: UUID, now: datetime) -> list[Session]:
        rows = await self._session.scalars(
            select(Session)
            .where(Session.user_id == user_id, Session.expires_at > now)
            .order_by(Session.created_at, Session.id)
        )
        return list(rows)

    async def delete(self, user_id: UUID, session_id: UUID) -> bool:
        """Delete the user's session. False when the user has no such session."""
        deleted = await self._session.scalar(
            delete(Session)
            .where(Session.id == session_id, Session.user_id == user_id)
            .returning(Session.id)
        )
        return deleted is not None
