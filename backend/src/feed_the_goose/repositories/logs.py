"""Logs (owned by T06 after T04)."""

from datetime import date
from uuid import UUID

from sqlalchemy import exists, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Log


class LogRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def insert(self, log: Log) -> bool:
        """Insert unless a log with this ID exists. True when the row is new."""
        values = {c.key: getattr(log, c.key) for c in Log.__table__.columns}
        inserted = await self._session.scalar(
            insert(Log).values(values).on_conflict_do_nothing().returning(Log.id)
        )
        return inserted is not None

    async def get(self, log_id: UUID) -> Log | None:
        """The log with this ID, whoever it belongs to."""
        return await self._session.get(Log, log_id)

    async def for_day(self, user_id: UUID, day: date) -> list[Log]:
        """The day's logs, undone ones included, in the order they count."""
        rows = await self._session.scalars(
            select(Log)
            .where(Log.user_id == user_id, Log.date == day)
            .order_by(Log.logged_at, Log.id)
        )
        return list(rows)

    async def exists_for_day(self, user_id: UUID, day: date) -> bool:
        """Whether any log, undone or not, has been made in the day."""
        found = await self._session.scalar(
            select(exists().where(Log.user_id == user_id, Log.date == day))
        )
        return bool(found)
