"""The key routes (API spec "Keys", constitution §6).

A key is `ftg_` plus 32 random bytes, URL-safe, shown once and stored as its SHA-256
digest. It works only where its kind belongs, and revoking it stops it at once.
"""

import hashlib
import re
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import select

from feed_the_goose.models import Key

pytestmark = pytest.mark.anyio

SECRET = re.compile(r"ftg_[A-Za-z0-9_-]{43}")  # 32 bytes, URL-safe, unpadded


async def test_a_new_key_returns_its_secret_once_and_stores_only_its_digest(
    sign_in, db, clock
):
    user = await sign_in()

    response = await user.client.post(
        "/v1/me/keys", json={"kind": "mcp", "name": "Claude Code"}
    )

    assert response.status_code == 201, response.text
    created = response.json()
    assert SECRET.fullmatch(created["secret"])
    assert created["kind"] == "mcp"
    assert created["name"] == "Claude Code"
    assert created["created_at"] == "2026-11-26T15:00:00Z"
    assert created["last_used_at"] is None
    (row,) = await db.scalars(select(Key).where(Key.user_id == user.user_id))
    assert row.digest == hashlib.sha256(created["secret"].encode()).hexdigest()
    listed = (await user.client.get("/v1/me/keys")).json()
    assert listed == [
        {
            "id": created["id"],
            "kind": "mcp",
            "name": "Claude Code",
            "created_at": "2026-11-26T15:00:00Z",
            "last_used_at": None,
        }
    ]


async def test_each_key_has_its_own_secret(sign_in):
    user = await sign_in()

    first = await user.client.post("/v1/me/keys", json={"kind": "api", "name": "a"})
    second = await user.client.post("/v1/me/keys", json={"kind": "api", "name": "a"})

    assert first.json()["secret"] != second.json()["secret"]
    assert first.json()["id"] != second.json()["id"]


async def test_an_api_key_works_at_v1_and_an_mcp_key_does_not(sign_in, client):
    user = await sign_in()
    api = (
        await user.client.post("/v1/me/keys", json={"kind": "api", "name": "script"})
    ).json()
    mcp = (
        await user.client.post("/v1/me/keys", json={"kind": "mcp", "name": "agent"})
    ).json()

    with_api = await client.get(
        "/v1/me", headers={"Authorization": f"Bearer {api['secret']}"}
    )
    with_mcp = await client.get(
        "/v1/me", headers={"Authorization": f"Bearer {mcp['secret']}"}
    )

    assert with_api.status_code == 200
    assert with_api.json()["id"] == str(user.user_id)
    assert with_mcp.status_code == 401


async def test_a_key_shows_when_it_was_last_used(sign_in, client, clock):
    user = await sign_in()
    created = (
        await user.client.post("/v1/me/keys", json={"kind": "api", "name": "script"})
    ).json()
    clock.set(clock.now() + timedelta(minutes=5))

    await client.get("/v1/me", headers={"Authorization": f"Bearer {created['secret']}"})

    (listed,) = (await user.client.get("/v1/me/keys")).json()
    assert listed["last_used_at"] == "2026-11-26T15:05:00Z"


async def test_a_revoked_key_stops_on_its_next_call_and_leaves_the_list(
    sign_in, client
):
    user = await sign_in()
    kept = (
        await user.client.post("/v1/me/keys", json={"kind": "api", "name": "kept"})
    ).json()
    revoked = (
        await user.client.post("/v1/me/keys", json={"kind": "api", "name": "gone"})
    ).json()
    headers = {"Authorization": f"Bearer {revoked['secret']}"}
    assert (await client.get("/v1/me", headers=headers)).status_code == 200

    response = await user.client.delete(f"/v1/me/keys/{revoked['id']}")

    assert response.status_code == 204
    assert (await client.get("/v1/me", headers=headers)).status_code == 401
    listed = (await user.client.get("/v1/me/keys")).json()
    assert [k["id"] for k in listed] == [kept["id"]]


async def test_revoking_an_unknown_revoked_or_another_users_key_is_not_found(
    sign_in,
):
    owner = await sign_in()
    other = await sign_in()
    key = (
        await owner.client.post("/v1/me/keys", json={"kind": "mcp", "name": "agent"})
    ).json()

    by_other = await other.client.delete(f"/v1/me/keys/{key['id']}")
    unknown = await owner.client.delete(f"/v1/me/keys/{uuid.uuid4()}")
    first = await owner.client.delete(f"/v1/me/keys/{key['id']}")
    again = await owner.client.delete(f"/v1/me/keys/{key['id']}")

    assert by_other.status_code == 404
    assert unknown.status_code == 404
    assert first.status_code == 204
    assert again.status_code == 404
    assert again.json()["type"] == "not_found"


async def test_a_user_lists_only_their_own_keys(sign_in):
    owner = await sign_in()
    other = await sign_in()
    await owner.client.post("/v1/me/keys", json={"kind": "api", "name": "mine"})

    assert (await other.client.get("/v1/me/keys")).json() == []


@pytest.mark.parametrize(
    "body",
    [
        {"kind": "session", "name": "x"},
        {"kind": "api", "name": ""},
        {"kind": "api"},
    ],
)
async def test_an_invalid_key_request_is_refused(sign_in, body):
    user = await sign_in()

    response = await user.client.post("/v1/me/keys", json=body)

    assert response.status_code == 422
    assert response.json()["type"] == "invalid"
    assert (await user.client.get("/v1/me/keys")).json() == []
