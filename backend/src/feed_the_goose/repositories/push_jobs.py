"""Planned reminders (owned by T09 after T04)."""

from datetime import date, datetime
from uuid import UUID

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import PushJob


class PushJobRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, job: PushJob) -> PushJob:
        self._session.add(job)
        await self._session.flush()
        return job

    async def for_day(self, user_id: UUID, day: date) -> list[PushJob]:
        rows = await self._session.scalars(
            select(PushJob)
            .where(PushJob.user_id == user_id, PushJob.date == day)
            .order_by(PushJob.due_at)
        )
        return list(rows)

    async def delete_unsent(self, user_id: UUID, day: date) -> None:
        await self._session.execute(
            delete(PushJob).where(
                PushJob.user_id == user_id,
                PushJob.date == day,
                PushJob.sent_at.is_(None),
            )
        )

    async def claim_due(self, now: datetime, limit: int) -> list[PushJob]:
        """Unsent jobs that are due, locked so that another worker skips them."""
        rows = await self._session.scalars(
            select(PushJob)
            .where(PushJob.sent_at.is_(None), PushJob.due_at <= now)
            .order_by(PushJob.due_at)
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        return list(rows)

    async def mark_sent(self, job_id: UUID, now: datetime) -> None:
        await self._session.execute(
            update(PushJob)
            .where(PushJob.id == job_id)
            .values(sent_at=now, attempts=PushJob.attempts + 1)
        )
