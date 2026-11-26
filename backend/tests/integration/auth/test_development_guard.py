"""The dev sign-in and /dev routes never run in production (TDD §5.6)."""

import pytest

from feed_the_goose import wiring
from feed_the_goose.app import create_app
from feed_the_goose.config import Settings
from feed_the_goose.identity.dev import DevelopmentGuardError


@pytest.mark.parametrize(
    ("sign_in", "routes"), [(True, False), (False, True), (True, True)]
)
def test_production_with_a_development_switch_refuses_to_start(sign_in, routes):
    settings = Settings(
        _env_file=None,
        env="production",
        dev_sign_in_enabled=sign_in,
        dev_routes_enabled=routes,
    )

    with pytest.raises(DevelopmentGuardError):
        create_app(wiring.build(settings))


@pytest.mark.anyio
async def test_production_without_the_switches_has_no_dev_routes():
    import httpx

    settings = Settings(_env_file=None, env="production")
    app = create_app(wiring.build(settings))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        response = await c.post("/dev/token", json={"email": "matt@example.com"})

    assert response.status_code == 404


@pytest.mark.anyio
async def test_dev_routes_on_without_the_dev_sign_in_issue_no_tokens():
    import httpx

    settings = Settings(_env_file=None, env="development", dev_routes_enabled=True)
    app = create_app(wiring.build(settings))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        response = await c.post("/dev/token", json={"email": "matt@example.com"})

    assert response.status_code == 404
