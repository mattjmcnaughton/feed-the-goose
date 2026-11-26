"""Days (owned by T06 after T04)."""

from datetime import date
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Day


class DayRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, day: Day) -> Day:
        self._session.add(day)
        await self._session.flush()
        return day

    async def get(self, user_id: UUID, day: date) -> Day | None:
        return await self._session.scalar(
            select(Day).where(Day.user_id == user_id, Day.date == day)
        )

    async def latest(self, user_id: UUID) -> Day | None:
        return await self._session.scalar(
            select(Day).where(Day.user_id == user_id).order_by(Day.date.desc()).limit(1)
        )

    async def before(self, user_id: UUID, day: date) -> Day | None:
        """The user's latest day before `day`."""
        return await self._session.scalar(
            select(Day)
            .where(Day.user_id == user_id, Day.date < day)
            .order_by(Day.date.desc())
            .limit(1)
        )

    async def between(self, user_id: UUID, first: date, last: date) -> list[Day]:
        """The user's days from `first` to `last`, both included, oldest first."""
        rows = await self._session.scalars(
            select(Day)
            .where(Day.user_id == user_id, Day.date >= first, Day.date <= last)
            .order_by(Day.date)
        )
        return list(rows)
