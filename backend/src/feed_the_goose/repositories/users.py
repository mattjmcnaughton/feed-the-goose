"""Users (owned by T05 after T04)."""

from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import User


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, user: User) -> User:
        self._session.add(user)
        await self._session.flush()
        return user

    async def get(self, user_id: UUID) -> User | None:
        return await self._session.get(User, user_id)

    async def by_identity_subject(self, subject: str) -> User | None:
        return await self._session.scalar(
            select(User).where(User.identity_subject == subject)
        )

    async def lock(self, user_id: UUID) -> User | None:
        """Read the user's row and lock it until the transaction ends."""
        return await self._session.scalar(
            select(User).where(User.id == user_id).with_for_update()
        )

    async def delete(self, user_id: UUID) -> None:
        """Delete the user. Every other row of theirs goes with it (cascade)."""
        await self._session.execute(delete(User).where(User.id == user_id))
