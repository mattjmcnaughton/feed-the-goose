"""Sign-in and app sessions (API spec "Auth", constitution §6)."""

import hashlib
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import text

pytestmark = pytest.mark.anyio


@pytest.fixture
def email() -> str:
    """An email no other test in this run's database has used."""
    return f"matt-{uuid.uuid4().hex[:8]}@example.com"


async def _identity_token(client, email: str) -> str:
    response = await client.post("/dev/token", json={"email": email})
    assert response.status_code == 200
    return response.json()["identity_token"]


async def _session(client, token: str, time_zone: str = "America/New_York"):
    return await client.post(
        "/v1/auth/session",
        json={
            "auth0_access_token": token,
            "time_zone": time_zone,
            "device_name": "iPhone",
        },
    )


async def test_sign_in_creates_the_account_with_the_default_day(
    client, settings, email
):
    settings.allowed_emails = (email,)
    token = await _identity_token(client, email.upper())

    response = await _session(client, token)

    assert response.status_code == 201
    body = response.json()
    assert body["expires_at"] == "2027-02-24T15:00:00Z"  # 90 days after 15:00Z
    user = body["user"]
    assert user["email"] == email
    assert user["pursuer"] == "goose"
    assert (user["time_zone"], user["day_start"], user["day_end"]) == (
        "America/New_York",
        "06:00",
        "00:00",
    )
    assert user["pending"] is None


async def test_a_second_sign_in_reuses_the_account_and_ignores_its_time_zone(
    client, settings, email
):
    settings.allowed_emails = (email,)
    first = await _session(client, await _identity_token(client, email))
    again = await _session(
        client,
        await _identity_token(client, email),
        time_zone="Europe/London",
    )

    assert again.status_code == 201
    assert again.json()["user"]["id"] == first.json()["user"]["id"]
    assert again.json()["user"]["time_zone"] == "America/New_York"
    assert again.json()["session_token"] != first.json()["session_token"]


async def test_an_email_off_the_allowlist_is_not_admitted(client, settings, email):
    settings.allowed_emails = (email,)
    token = await _identity_token(client, "stranger@example.com")

    response = await _session(client, token)

    assert response.status_code == 403
    assert response.json()["type"] == "identity_not_admitted"


async def test_an_unverifiable_identity_token_is_unauthenticated(
    client, settings, email
):
    settings.allowed_emails = (email,)

    response = await _session(client, "not-a-token")

    assert response.status_code == 401
    assert response.json()["type"] == "unauthenticated"


async def test_an_expired_dev_token_is_unauthenticated(client, settings, email, clock):
    settings.allowed_emails = (email,)
    token = await _identity_token(client, email)
    clock.set(clock.now() + timedelta(minutes=11))

    assert (await _session(client, token)).status_code == 401


async def test_an_unknown_time_zone_is_invalid_on_sign_up(client, settings, email):
    settings.allowed_emails = (email,)
    token = await _identity_token(client, email)

    response = await _session(client, token, time_zone="Mars/Olympus")

    assert response.status_code == 422
    assert response.json()["errors"] == [
        {"field": "time_zone", "message": "Value is not valid"}
    ]


async def test_sessions_list_marks_the_current_one(sign_in, email):
    phone = await sign_in(email=email)
    laptop = await sign_in(email=email)

    response = await phone.client.get("/v1/auth/sessions")

    assert response.status_code == 200
    sessions = response.json()
    assert len(sessions) == 2
    (phone_current,) = [s["id"] for s in sessions if s["current"]]
    assert all(s["device_name"] == "Test device" for s in sessions)
    other = (await laptop.client.get("/v1/auth/sessions")).json()
    (laptop_current,) = [s["id"] for s in other if s["current"]]
    assert {phone_current, laptop_current} == {s["id"] for s in sessions}


async def test_signing_out_stops_the_token_on_its_next_call(sign_in, email):
    user = await sign_in()

    signed_out = await user.client.delete("/v1/auth/sessions/current")

    assert signed_out.status_code == 204
    after = await user.client.get("/v1/auth/sessions")
    assert after.status_code == 401
    assert after.json()["type"] == "unauthenticated"
    assert after.headers["www-authenticate"] == "Bearer"


async def test_deleting_another_device_session_by_id(sign_in, email):
    phone = await sign_in(email=email)
    laptop = await sign_in(email=email)
    sessions = (await phone.client.get("/v1/auth/sessions")).json()
    (laptop_session,) = [s for s in sessions if not s["current"]]

    deleted = await phone.client.delete(f"/v1/auth/sessions/{laptop_session['id']}")

    assert deleted.status_code == 204
    assert (await laptop.client.get("/v1/auth/sessions")).status_code == 401
    assert (await phone.client.get("/v1/auth/sessions")).status_code == 200


async def test_another_users_session_is_not_found(sign_in, email):
    mine = await sign_in()
    theirs = await sign_in()
    (their_session,) = (await theirs.client.get("/v1/auth/sessions")).json()

    response = await mine.client.delete(f"/v1/auth/sessions/{their_session['id']}")

    assert response.status_code == 404
    assert response.json()["type"] == "not_found"
    assert (await theirs.client.get("/v1/auth/sessions")).status_code == 200


async def test_a_session_expires_after_90_days_without_use(sign_in, clock):
    user = await sign_in()
    clock.set(clock.now() + timedelta(days=89))
    assert (await user.client.get("/v1/auth/sessions")).status_code == 200

    # Each use extends it, so 89 more days is still within the lifetime.
    clock.set(clock.now() + timedelta(days=89))
    assert (await user.client.get("/v1/auth/sessions")).status_code == 200

    clock.set(clock.now() + timedelta(days=90, seconds=1))
    assert (await user.client.get("/v1/auth/sessions")).status_code == 401


async def test_only_the_tokens_digest_is_stored(sign_in, db):
    user = await sign_in()

    rows = (
        await db.execute(
            text("SELECT * FROM sessions WHERE user_id = :u"), {"u": user.user_id}
        )
    ).mappings()
    (row,) = list(rows)

    assert row["token_digest"] == hashlib.sha256(user.token.encode()).hexdigest()
    assert user.token not in {str(v) for v in row.values()}


async def test_two_simultaneous_first_sign_ins_make_one_account(
    client, settings, email
):
    import asyncio

    settings.allowed_emails = (email,)
    token = await _identity_token(client, email)

    responses = await asyncio.gather(_session(client, token), _session(client, token))

    assert [r.status_code for r in responses] == [201, 201]
    assert len({r.json()["user"]["id"] for r in responses}) == 1
