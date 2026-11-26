"""API and MCP keys (API spec "Keys", constitution §6).

A key is `ftg_` plus 32 random bytes, URL-safe. Its secret is returned once, when it
is created; only its SHA-256 digest is stored. `AuthService.authenticate` checks the
digest on every request, so a revoked key stops on its next call.
"""

import secrets
from dataclasses import dataclass
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.models import Key
from feed_the_goose.repositories.keys import KeyRepository
from feed_the_goose.services.auth import CredentialKind, Principal, digest

PREFIX = "ftg_"

# The kinds a user can create. A session is not a key.
KEY_KINDS = frozenset({CredentialKind.api, CredentialKind.mcp})


class KeyNotFoundError(Exception):
    """The user has no such active key."""


@dataclass(frozen=True)
class CreatedKey:
    key: Key
    secret: str


class KeyService:
    def __init__(
        self, *, clock: Clock, sessions: async_sessionmaker[AsyncSession]
    ) -> None:
        self._clock = clock
        self._sessions = sessions

    async def listed(self, principal: Principal) -> list[Key]:
        """The user's active keys, oldest first."""
        async with self._sessions.begin() as db:
            return await KeyRepository(db).active_for_user(principal.user_id)

    async def create(
        self, principal: Principal, kind: CredentialKind, name: str
    ) -> CreatedKey:
        assert kind in KEY_KINDS
        secret = PREFIX + secrets.token_urlsafe(32)
        async with self._sessions.begin() as db:
            key = await KeyRepository(db).add(
                Key(
                    user_id=principal.user_id,
                    kind=kind.value,
                    name=name,
                    digest=digest(secret),
                    created_at=self._clock.now(),
                    last_used_at=None,
                    revoked_at=None,
                )
            )
        return CreatedKey(key=key, secret=secret)

    async def revoke(self, principal: Principal, key_id: UUID) -> None:
        async with self._sessions.begin() as db:
            if not await KeyRepository(db).revoke(
                principal.user_id, key_id, self._clock.now()
            ):
                raise KeyNotFoundError
