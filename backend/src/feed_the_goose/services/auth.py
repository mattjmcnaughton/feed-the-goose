"""Sign-in, app sessions and resolving credentials (TDD §5.6, constitution §6)."""

import hashlib
import secrets
from collections.abc import Collection, Sequence
from dataclasses import dataclass
from datetime import date, time, timedelta
from enum import StrEnum
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.identity import (
    IdentityVerifier,
    InvalidIdentityTokenError,
    VerifiedIdentity,
)
from feed_the_goose.models import DaySettings, Session, User
from feed_the_goose.repositories.day_settings import DaySettingsRepository
from feed_the_goose.repositories.keys import KeyRepository
from feed_the_goose.repositories.sessions import SessionRepository
from feed_the_goose.repositories.users import UserRepository


class CredentialKind(StrEnum):
    session = "session"
    api = "api"
    mcp = "mcp"


@dataclass(frozen=True)
class Principal:
    """The authenticated account and the credential it used."""

    user_id: UUID
    kind: CredentialKind
    # The app session making the request, for `current`; None for a key.
    session_id: UUID | None = None


class UnauthenticatedError(Exception):
    """No accepted credential matches."""


class NotAdmittedError(Exception):
    """A verified identity whose email is not on the allowlist."""


class InvalidTimeZoneError(Exception):
    pass


class SessionNotFoundError(Exception):
    pass


@dataclass(frozen=True)
class SignedIn:
    token: str
    session: Session
    user: User


@dataclass(frozen=True)
class SessionList:
    sessions: list[Session]
    current: UUID | None


def digest(secret: str) -> str:
    """The SHA-256 digest stored in place of a secret."""
    return hashlib.sha256(secret.encode()).hexdigest()


class AuthService:
    def __init__(
        self,
        *,
        settings: Settings,
        clock: Clock,
        sessions: async_sessionmaker[AsyncSession],
        verifiers: Sequence[IdentityVerifier],
    ) -> None:
        self._settings = settings
        self._clock = clock
        self._sessions = sessions
        self._verifiers = verifiers

    async def sign_in(
        self, identity_token: str, time_zone: str, device_name: str
    ) -> SignedIn:
        """Swap a verified identity token for a new app session.

        The account is created on first sign-in, with `time_zone` and the default
        day hours. Only the session token's digest is stored.
        """
        identity = await self._verify(identity_token)
        if (
            not identity.email_verified
            or identity.email not in self._settings.allowed_emails
        ):
            raise NotAdmittedError
        now = self._clock.now()
        token = secrets.token_urlsafe(32)
        async with self._sessions.begin() as db:
            users = UserRepository(db)
            user = await users.by_identity_subject(identity.subject)
            if user is None:
                user = await self._create_user(db, identity, time_zone)
            if user is None:  # a simultaneous first sign-in created it
                user = await users.by_identity_subject(identity.subject)
            assert user is not None
            session = await SessionRepository(db).add(
                Session(
                    user_id=user.id,
                    token_digest=digest(token),
                    device_name=device_name,
                    created_at=now,
                    last_used_at=now,
                    expires_at=now + self._lifetime,
                )
            )
        return SignedIn(token=token, session=session, user=user)

    async def authenticate(
        self, secret: str, kinds: Collection[CredentialKind]
    ) -> Principal:
        """Resolve a bearer secret to a principal, if it is one of `kinds`.

        The digest is checked on every request, so a deleted session or a revoked
        key stops on its next call. A session's lifetime is extended on each use.
        """
        found = digest(secret)
        now = self._clock.now()
        async with self._sessions.begin() as db:
            if CredentialKind.session in kinds:
                session = await SessionRepository(db).active_by_digest(found, now)
                if session is not None:
                    session.last_used_at = now
                    session.expires_at = now + self._lifetime
                    return Principal(
                        session.user_id, CredentialKind.session, session.id
                    )
            key_kinds = {k.value for k in kinds} - {CredentialKind.session.value}
            if key_kinds:
                key = await KeyRepository(db).active_by_digest(found)
                if key is not None and key.kind in key_kinds:
                    key.last_used_at = now
                    return Principal(key.user_id, CredentialKind(key.kind))
        raise UnauthenticatedError

    async def list_sessions(self, principal: Principal) -> SessionList:
        async with self._sessions.begin() as db:
            rows = await SessionRepository(db).active_for_user(
                principal.user_id, self._clock.now()
            )
        return SessionList(sessions=rows, current=principal.session_id)

    async def delete_session(self, principal: Principal, session_id: str) -> None:
        """Delete one of the user's sessions. `current` is the calling session."""
        if session_id == "current":
            target = principal.session_id
        else:
            try:
                target = UUID(session_id)
            except ValueError:
                raise SessionNotFoundError from None
        async with self._sessions.begin() as db:
            if target is None or not await SessionRepository(db).delete(
                principal.user_id, target
            ):
                raise SessionNotFoundError

    @property
    def _lifetime(self) -> timedelta:
        return timedelta(days=self._settings.session_lifetime_days)

    async def _verify(self, token: str) -> VerifiedIdentity:
        for verifier in self._verifiers:
            try:
                return await verifier.verify(token)
            except InvalidIdentityTokenError:
                continue
        raise UnauthenticatedError

    async def _create_user(
        self, db: AsyncSession, identity: VerifiedIdentity, time_zone: str
    ) -> User | None:
        """Create the account, or return None when another request just did."""
        try:
            zone = ZoneInfo(time_zone)
        except (ZoneInfoNotFoundError, ValueError):
            raise InvalidTimeZoneError from None
        now = self._clock.now()
        user = User(
            identity_subject=identity.subject,
            email=identity.email,
            display_name=identity.email.split("@")[0],
            pursuer=self._settings.pursuers[0],
            public=False,
            reminders_enabled=False,
            reminder_lead_below=self._settings.reminder_lead_below,
            id=uuid4(),
            created_at=now,
        )
        if not await UserRepository(db).add_unless_subject_exists(user):
            return None
        # From the day before the local date, so that the settings also cover a
        # sign-up during the night, which belongs to the day that just ended.
        effective_from: date = now.astimezone(zone).date() - timedelta(days=1)
        await DaySettingsRepository(db).add(
            DaySettings(
                user_id=user.id,
                effective_from=effective_from,
                time_zone=time_zone,
                day_start=time.fromisoformat(self._settings.default_day_start),
                day_end=time.fromisoformat(self._settings.default_day_end),
                created_at=now,
            )
        )
        return user
