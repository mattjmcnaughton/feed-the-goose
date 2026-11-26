"""Needs Postgres at DATABASE_URL: run `just db-up` and `just migrate` first."""

import httpx
import pytest

from feed_the_goose.app import create_app


@pytest.mark.anyio
async def test_readyz_answers_200_when_the_database_answers():
    transport = httpx.ASGITransport(app=create_app())
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        response = await c.get("/readyz")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}
