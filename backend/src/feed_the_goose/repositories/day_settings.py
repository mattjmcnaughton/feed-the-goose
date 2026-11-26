"""Day settings, append-only (owned by T05 after T04)."""

from datetime import date
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import DaySettings


class DaySettingsRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, row: DaySettings) -> DaySettings:
        self._session.add(row)
        await self._session.flush()
        return row

    async def for_user(self, user_id: UUID) -> list[DaySettings]:
        """Every row of the user's, oldest `effective_from` first."""
        rows = await self._session.scalars(
            select(DaySettings)
            .where(DaySettings.user_id == user_id)
            .order_by(DaySettings.effective_from)
        )
        return list(rows)

    async def effective_on(self, user_id: UUID, day: date) -> DaySettings | None:
        """The row for `day`: the latest `effective_from` on or before it."""
        return await self._session.scalar(
            select(DaySettings)
            .where(DaySettings.user_id == user_id, DaySettings.effective_from <= day)
            .order_by(DaySettings.effective_from.desc())
            .limit(1)
        )
