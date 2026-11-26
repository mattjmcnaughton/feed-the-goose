"""Shared fixtures (TDD §7).

Integration tests get a database made for this test run by the real migrations, an
app wired to it with a fixed clock, and `sign_in`, which returns a client signed in
as a new user through the dev sign-in.
"""

import uuid
from collections.abc import AsyncIterator, Awaitable, Callable, Iterator
from dataclasses import dataclass
from datetime import UTC, datetime

import httpx
import pytest
from fastapi import FastAPI
from sqlalchemy import pool
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine

from feed_the_goose import wiring
from feed_the_goose.app import create_app
from feed_the_goose.clock import FixedClock
from feed_the_goose.config import Settings
from tests.support import database

# 10:00 in New York on the TDD §5.3 example day.
NOW = datetime(2026, 11, 26, 15, tzinfo=UTC)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture(scope="session")
def database_url() -> Iterator[str]:
    """A migrated database for this test run, dropped at the end."""
    base = Settings(_env_file=None).database_url
    url = database.create(base)
    try:
        yield url
    finally:
        database.drop(base, url)


@pytest.fixture
def settings(database_url: str) -> Settings:
    return Settings(
        _env_file=None,
        env="test",
        database_url=database_url,
        dev_sign_in_enabled=True,
        dev_routes_enabled=True,
        allowed_emails=(),
    )


@pytest.fixture
def clock() -> FixedClock:
    return FixedClock(NOW)


@pytest.fixture
async def engine(settings: Settings) -> AsyncIterator[AsyncEngine]:
    engine = create_async_engine(settings.database_url, poolclass=pool.NullPool)
    yield engine
    await engine.dispose()


@pytest.fixture
def wired(settings: Settings, clock: FixedClock, engine: AsyncEngine) -> wiring.Wiring:
    return wiring.build(settings, clock, engine)


@pytest.fixture
def app(wired: wiring.Wiring) -> FastAPI:
    return create_app(wired)


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture
async def db(wired: wiring.Wiring) -> AsyncIterator[AsyncSession]:
    """A session for builders and assertions. Commit to make rows visible."""
    async with wired.sessions() as session:
        yield session


@dataclass
class SignedIn:
    client: httpx.AsyncClient
    user_id: uuid.UUID
    email: str
    token: str


SignInFactory = Callable[..., Awaitable[SignedIn]]


@pytest.fixture
async def sign_in(
    app: FastAPI, settings: Settings, client: httpx.AsyncClient
) -> AsyncIterator[SignInFactory]:
    """Sign in as a new user, admitted for the test, through `/dev/token`."""
    opened: list[httpx.AsyncClient] = []

    async def factory(
        email: str | None = None, time_zone: str = "America/New_York"
    ) -> SignedIn:
        email = email or f"user-{uuid.uuid4().hex[:8]}@example.com"
        settings.allowed_emails = (*settings.allowed_emails, email)
        token = (await client.post("/dev/token", json={"email": email})).json()
        response = await client.post(
            "/v1/auth/session",
            json={
                "auth0_access_token": token["identity_token"],
                "time_zone": time_zone,
                "device_name": "Test device",
            },
        )
        assert response.status_code == 201, response.text
        body = response.json()
        signed_in = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {body['session_token']}"},
        )
        opened.append(signed_in)
        return SignedIn(
            signed_in, uuid.UUID(body["user"]["id"]), email, body["session_token"]
        )

    yield factory
    for c in opened:
        await c.aclose()
