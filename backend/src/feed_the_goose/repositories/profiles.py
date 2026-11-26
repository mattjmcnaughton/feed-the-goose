"""Profile handles and publication (owned by T08)."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import User


class ProfileRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def published(self, handle: str) -> UUID | None:
        """The user who published a profile at `handle`, if one did."""
        return await self._session.scalar(
            select(User.id).where(User.handle == handle, User.public.is_(True))
        )

    async def holder(self, handle: str) -> UUID | None:
        """The user who holds `handle`, published or not."""
        return await self._session.scalar(select(User.id).where(User.handle == handle))
