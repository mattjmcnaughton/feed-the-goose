"""Installations and their push tokens (owned by T09 after T04)."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Installation


class InstallationRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def upsert(
        self,
        user_id: UUID,
        installation_id: str,
        *,
        apns_token: str | None,
        widget_push_token: str | None,
        environment: str,
        app_version: str,
        now: datetime,
    ) -> None:
        """Register an installation, or refresh its tokens."""
        fields = {
            "apns_token": apns_token,
            "widget_push_token": widget_push_token,
            "environment": environment,
            "app_version": app_version,
            "updated_at": now,
        }
        await self._session.execute(
            insert(Installation)
            .values(
                user_id=user_id,
                installation_id=installation_id,
                created_at=now,
                **fields,
            )
            .on_conflict_do_update(
                index_elements=["user_id", "installation_id"], set_=fields
            )
        )

    async def for_user(self, user_id: UUID) -> list[Installation]:
        rows = await self._session.scalars(
            select(Installation)
            .where(Installation.user_id == user_id)
            .order_by(Installation.created_at)
        )
        return list(rows)

    async def delete(self, user_id: UUID, installation_id: str) -> None:
        await self._session.execute(
            delete(Installation).where(
                Installation.user_id == user_id,
                Installation.installation_id == installation_id,
            )
        )
