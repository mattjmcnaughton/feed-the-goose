"""Installations and their push tokens (API spec "Devices and push")."""

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.repositories.installations import InstallationRepository
from feed_the_goose.services.accounts import lock_user
from feed_the_goose.services.auth import Principal


@dataclass(frozen=True)
class Registration:
    apns_token: str
    widget_push_token: str | None
    environment: str
    app_version: str


class InstallationService:
    def __init__(
        self, *, clock: Clock, sessions: async_sessionmaker[AsyncSession]
    ) -> None:
        self._clock = clock
        self._sessions = sessions

    async def register(
        self, principal: Principal, installation_id: UUID, registration: Registration
    ) -> None:
        """Register this installation, or refresh its tokens."""
        async with self._sessions.begin() as db:
            await lock_user(db, principal)
            await InstallationRepository(db).upsert(
                principal.user_id,
                str(installation_id),
                apns_token=registration.apns_token,
                widget_push_token=registration.widget_push_token,
                environment=registration.environment,
                app_version=registration.app_version,
                now=self._clock.now(),
            )

    async def delete(self, principal: Principal, installation_id: UUID) -> None:
        """Forget this installation. Deleting one that is gone does nothing."""
        async with self._sessions.begin() as db:
            await InstallationRepository(db).delete(
                principal.user_id, str(installation_id)
            )
