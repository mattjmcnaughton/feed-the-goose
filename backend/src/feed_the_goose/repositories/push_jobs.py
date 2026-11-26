"""Planned reminders and the recording sender's deliveries (owned by T09 after T04)."""

from datetime import date, datetime
from uuid import UUID

from sqlalchemy import delete, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import PushDelivery, PushJob, User


class PushJobRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def users_with_reminders(self) -> list[UUID]:
        rows = await self._session.scalars(
            select(User.id).where(User.reminders_enabled).order_by(User.created_at)
        )
        return list(rows)

    async def for_day(self, user_id: UUID, day: date) -> list[PushJob]:
        rows = await self._session.scalars(
            select(PushJob)
            .where(PushJob.user_id == user_id, PushJob.date == day)
            .order_by(PushJob.due_at)
        )
        return list(rows)

    async def replace_unsent(
        self, user_id: UUID, day: date, jobs: list[PushJob]
    ) -> None:
        """Replace the day's unsent jobs with `jobs`. A kind already sent that day
        is kept as it is, so it is not sent again."""
        await self.delete_unsent(user_id, day)
        for job in jobs:
            await self._session.execute(
                insert(PushJob)
                .values(
                    user_id=user_id,
                    date=day,
                    kind=job.kind,
                    due_at=job.due_at,
                    payload=job.payload,
                    attempts=0,
                )
                .on_conflict_do_nothing(index_elements=["user_id", "date", "kind"])
            )

    async def delete_unsent(self, user_id: UUID, day: date | None = None) -> None:
        """Delete the unsent jobs of `day`, or of every day."""
        query = delete(PushJob).where(
            PushJob.user_id == user_id, PushJob.sent_at.is_(None)
        )
        if day is not None:
            query = query.where(PushJob.date == day)
        await self._session.execute(query)

    async def claim_due(
        self,
        now: datetime,
        *,
        since: datetime,
        max_attempts: int,
        exclude: list[UUID],
        limit: int,
    ) -> list[PushJob]:
        """Unsent jobs due between `since` and `now` with attempts left, other than
        `exclude`, locked so that another worker skips them."""
        rows = await self._session.scalars(
            select(PushJob)
            .where(
                PushJob.sent_at.is_(None),
                PushJob.due_at <= now,
                PushJob.due_at > since,
                PushJob.attempts < max_attempts,
                PushJob.id.not_in(exclude),
            )
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

    async def mark_failed(self, job_id: UUID) -> None:
        await self._session.execute(
            update(PushJob)
            .where(PushJob.id == job_id)
            .values(attempts=PushJob.attempts + 1)
        )

    async def deliveries(
        self, email: str | None, limit: int
    ) -> list[tuple[PushDelivery, str]]:
        """What the recording sender recorded, newest first, with each user's
        email."""
        query = (
            select(PushDelivery, User.email)
            .join(User, User.id == PushDelivery.user_id)
            .order_by(PushDelivery.sent_at.desc())
            .limit(limit)
        )
        if email is not None:
            query = query.where(User.email == email)
        return [(d, e) for d, e in (await self._session.execute(query)).all()]
