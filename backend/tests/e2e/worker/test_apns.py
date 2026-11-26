"""The worker sending through `ApnsSender` to a fake APNs that speaks HTTP/2 only
(TDD §5.9). The reminder is the one due at 17:12 (see `test_worker.py`)."""

import json
from datetime import UTC, datetime
from zoneinfo import ZoneInfo

import pytest
from joserfc import jwt
from joserfc.jwk import ECKey
from sqlalchemy import select

from feed_the_goose import wiring
from feed_the_goose.models import Installation, PushJob
from tests.e2e.worker.conftest import DEVICE_TOKEN

pytestmark = pytest.mark.anyio

KEY_ID, TEAM_ID = "KEY1234567", "TEAM123456"
DUE = datetime(2026, 11, 26, 17, 12, tzinfo=ZoneInfo("America/New_York")).astimezone(
    UTC
)


@pytest.fixture
def wired(settings, clock, engine, fake_apns, apns_key, tmp_path, monkeypatch):
    """The app wired with an APNs key, so that the worker sends to `fake_apns`."""
    key_path = tmp_path / "AuthKey_KEY1234567.p8"
    key_path.write_bytes(apns_key.as_pem(private=True))
    monkeypatch.setenv("APNS_KEY_PATH", str(key_path))
    monkeypatch.setenv("APNS_KEY_ID", KEY_ID)
    monkeypatch.setenv("APNS_TEAM_ID", TEAM_ID)
    monkeypatch.setenv("APNS_URL", fake_apns.url)
    return wiring.build(settings, clock, engine)


async def send_the_first_reminder(wired, clock) -> tuple[int, int]:
    await wired.reminders.run_pass()
    clock.set(DUE)
    return await wired.reminders.run_pass()


async def test_a_reminder_reaches_apns_as_apple_specifies(
    wired, account, clock, fake_apns, apns_key
):
    assert await send_the_first_reminder(wired, clock) == (0, 1)

    [request] = fake_apns.requests
    headers = request.headers
    assert headers[":method"] == "POST"
    assert headers[":path"] == f"/3/device/{DEVICE_TOKEN}"
    assert headers["apns-topic"] == "com.mattjmcnaughton.feedthegoose"
    assert headers["apns-push-type"] == "alert"
    assert headers["apns-priority"] == "10"

    scheme, token = headers["authorization"].split(" ")
    assert scheme == "bearer"
    public = ECKey.import_key(apns_key.as_pem(private=False))
    verified = jwt.decode(token, public, algorithms=["ES256"])
    assert verified.header == {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    assert verified.claims == {"iss": TEAM_ID, "iat": int(DUE.timestamp())}

    assert json.loads(request.body) == {
        "aps": {
            "alert": {
                "title": "Your lead is low",
                "body": "Your lead is below 60 steps. Log a habit to get ahead.",
            },
            "sound": "default",
            "thread-id": "reminders",
        },
        "kind": "lead_low",
        "date": "2026-11-26",
    }


async def test_a_410_deletes_the_token(wired, account, clock, fake_apns):
    fake_apns.status_for[DEVICE_TOKEN] = 410

    assert await send_the_first_reminder(wired, clock) == (0, 1)

    async with wired.sessions() as db:
        installation = await db.scalar(
            select(Installation).where(Installation.user_id == account.user_id)
        )
    assert installation is not None
    assert installation.apns_token is None

    # The day-end reminder at 23:00 has no token left to go to.
    clock.set(datetime(2026, 11, 27, 4, tzinfo=UTC))
    await wired.reminders.run_pass()
    assert len(fake_apns.requests) == 1


async def test_a_refused_reminder_is_tried_again_and_then_sent_once(
    wired, account, clock, fake_apns
):
    fake_apns.status_for[DEVICE_TOKEN] = 500
    assert await send_the_first_reminder(wired, clock) == (0, 0)

    del fake_apns.status_for[DEVICE_TOKEN]
    assert await wired.reminders.run_pass() == (0, 1)
    assert await wired.reminders.run_pass() == (0, 0)

    assert len(fake_apns.requests) == 2
    async with wired.sessions() as db:
        job = await db.scalar(
            select(PushJob).where(
                PushJob.user_id == account.user_id, PushJob.kind == "lead_low"
            )
        )
    assert job is not None
    assert (job.sent_at, job.attempts) == (DUE, 2)
