"""The one place that builds services from settings (TDD §5.1).

Tickets add their own registration lines here and nothing else.
"""

from dataclasses import dataclass
from typing import TYPE_CHECKING

import httpx
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock, SystemClock
from feed_the_goose.config import Settings
from feed_the_goose.identity.auth0 import Auth0Verifier
from feed_the_goose.identity.dev import DevIdentityTokens, check_development_guard
from feed_the_goose.services.accounts import AccountService, NoIdentityAdmin
from feed_the_goose.services.auth import AuthService

if TYPE_CHECKING:
    from feed_the_goose.identity import IdentityVerifier


@dataclass(frozen=True)
class Wiring:
    """The application's effects and services, built once."""

    settings: Settings
    clock: Clock
    sessions: async_sessionmaker[AsyncSession]
    auth: AuthService
    accounts: AccountService
    # Present only when the dev sign-in is on, outside production.
    dev_tokens: DevIdentityTokens | None


def build(
    settings: Settings, clock: Clock | None = None, engine: AsyncEngine | None = None
) -> Wiring:
    """Build the wiring from settings. Tests pass a fixed clock and their engine.

    Raises `DevelopmentGuardError` in production with a development switch on.
    """
    check_development_guard(settings)
    clock = clock or SystemClock()
    if engine is None:
        from feed_the_goose.db import engine as default_engine

        engine = default_engine
    sessions = async_sessionmaker(engine, expire_on_commit=False)

    verifiers: list[IdentityVerifier] = []
    dev_tokens = None
    if settings.dev_sign_in_enabled and settings.env != "production":
        dev_tokens = DevIdentityTokens(audience=settings.auth0_audience, clock=clock)
        verifiers.append(dev_tokens)
    if settings.auth0_issuer:
        verifiers.append(
            Auth0Verifier(
                issuer=settings.auth0_issuer,
                audience=settings.auth0_audience,
                clock=clock,
                http=httpx.AsyncClient(timeout=5),
            )
        )

    return Wiring(
        settings=settings,
        clock=clock,
        sessions=sessions,
        auth=AuthService(
            settings=settings, clock=clock, sessions=sessions, verifiers=verifiers
        ),
        accounts=AccountService(
            settings=settings,
            clock=clock,
            sessions=sessions,
            identity_admin=NoIdentityAdmin(),
        ),
        dev_tokens=dev_tokens,
    )
