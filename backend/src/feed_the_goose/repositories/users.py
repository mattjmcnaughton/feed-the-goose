"""Users (owned by T05 after T04)."""

from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import User


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, user: User) -> User:
        self._session.add(user)
        await self._session.flush()
        return user

    async def add_unless_subject_exists(self, user: User) -> bool:
        """Insert unless a user with this identity subject exists, waiting for a
        concurrent insert to finish. True when the row is new."""
        values = {
            c.key: getattr(user, c.key)
            for c in User.__table__.columns
            if getattr(user, c.key) is not None
        }
        inserted = await self._session.scalar(
            insert(User)
            .values(values)
            .on_conflict_do_nothing(index_elements=["identity_subject"])
            .returning(User.id)
        )
        return inserted is not None

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
