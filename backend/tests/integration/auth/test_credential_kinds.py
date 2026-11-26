"""Every /v1 route against every credential kind (API spec "Credentials").

The expected kinds are the spec's table, written out per operation. A route that
accepts the credential may answer anything but 401; a stub answers 501.
"""

import json
import re
import uuid
from pathlib import Path

import pytest

from tests.support import builders

pytestmark = pytest.mark.anyio

CLIENTS = Path(__file__).resolve().parents[4] / "clients"
CONTRACT = json.loads((CLIENTS / "openapi.json").read_text())
FIXTURES = [json.loads(p.read_text()) for p in (CLIENTS / "fixtures").glob("*.json")]

SESSION, API, MCP, NONE = "session", "api", "mcp", "none"
EVERY_V1 = {SESSION, API}
SESSION_ONLY = {SESSION}

# operationId -> the kinds it accepts. Public routes take no credential.
ACCEPTS: dict[str, set[str] | None] = {
    "createSession": None,
    "getPublicProfile": None,
    "listSessions": SESSION_ONLY,
    "deleteSession": SESSION_ONLY,
    "listKeys": SESSION_ONLY,
    "createKey": SESSION_ONLY,
    "deleteKey": SESSION_ONLY,
    "deleteMe": SESSION_ONLY,
    "getMe": EVERY_V1,
    "updateMe": EVERY_V1,
    "listHabits": EVERY_V1,
    "createHabit": EVERY_V1,
    "updateHabit": EVERY_V1,
    "archiveHabit": EVERY_V1,
    "createLog": EVERY_V1,
    "undoLog": EVERY_V1,
    "listLogs": EVERY_V1,
    "getChaseToday": EVERY_V1,
    "listDays": EVERY_V1,
    "getProfileSettings": EVERY_V1,
    "updateProfileSettings": EVERY_V1,
    "registerDevice": EVERY_V1,
    "deleteDevice": EVERY_V1,
    "getReminders": EVERY_V1,
    "updateReminders": EVERY_V1,
}

OPERATIONS = [
    (operation["operationId"], method.upper(), path)
    for path, methods in CONTRACT["paths"].items()
    for method, operation in methods.items()
]


def test_the_table_names_every_operation_in_the_contract():
    assert {op for op, _, _ in OPERATIONS} == set(ACCEPTS)


def _template_matches(template: str, path: str) -> bool:
    pattern = re.sub(r"\{[^}]+\}", "[^/]+", template)
    return re.fullmatch(pattern, path.split("?")[0]) is not None


def _request(method: str, template: str) -> tuple[str, dict | None]:
    """A path with IDs filled in, and a fixture's body for this route if any."""
    for fixture in FIXTURES:
        request = fixture["request"]
        if request["method"] == method and _template_matches(template, request["path"]):
            path = re.sub(r"\{[^}]+\}", str(uuid.uuid4()), template)
            query = request["path"].partition("?")[2]
            return path + (f"?{query}" if query else ""), request.get("body")
    return re.sub(r"\{[^}]+\}", str(uuid.uuid4()), template), None


CASES = [
    pytest.param(op, method, path, kind, id=f"{op}-{kind}")
    for op, method, path in OPERATIONS
    if ACCEPTS[op] is not None
    for kind in (SESSION, API, MCP, NONE)
]


@pytest.mark.parametrize(("operation", "method", "template", "kind"), CASES)
async def test_route_accepts_only_its_credential_kinds(
    operation, method, template, kind, sign_in, client, db
):
    user = await sign_in()
    headers = {}
    if kind == SESSION:
        headers["Authorization"] = f"Bearer {user.token}"
    elif kind in (API, MCP):
        secret = await builders.key(db, user.user_id, kind)
        await db.commit()
        headers["Authorization"] = f"Bearer {secret}"
    path, body = _request(method, template)

    response = await client.request(method, path, json=body, headers=headers)

    accepted = ACCEPTS[operation]
    assert accepted is not None
    if kind in accepted:
        assert response.status_code != 401, response.text
    else:
        assert response.status_code == 401, response.text
        assert response.json()["type"] == "unauthenticated"


async def test_a_revoked_api_key_stops_on_its_next_call(sign_in, client, db):
    user = await sign_in()
    revoked = await builders.key(db, user.user_id, "api", revoked=True)
    await db.commit()

    response = await client.get(
        "/v1/chase/today", headers={"Authorization": f"Bearer {revoked}"}
    )

    assert response.status_code == 401


async def test_an_api_key_records_its_last_use(sign_in, client, db, clock):
    user = await sign_in()
    secret = await builders.key(db, user.user_id, "api")
    await db.commit()

    await client.get("/v1/me", headers={"Authorization": f"Bearer {secret}"})

    from feed_the_goose.repositories.keys import KeyRepository

    (key,) = await KeyRepository(db).active_for_user(user.user_id)
    await db.refresh(key)
    assert key.last_used_at == clock.now()


async def test_a_non_bearer_authorization_is_unauthenticated(sign_in, client):
    user = await sign_in()

    response = await client.get(
        "/v1/auth/sessions", headers={"Authorization": f"Basic {user.token}"}
    )

    assert response.status_code == 401
