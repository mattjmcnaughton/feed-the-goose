"""The signed-in user and their settings (API spec "Me", constitution §4).

The clock is 10:00 in New York on 2026-11-26. A new user's day is 06:00 to 00:00.
"""

import dataclasses
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import select, text

from feed_the_goose.models import User
from feed_the_goose.services.accounts import AccountService
from tests.support import builders

pytestmark = pytest.mark.anyio

DEFAULT_DAY = {
    "time_zone": "America/New_York",
    "day_start": "06:00",
    "day_end": "00:00",
}


def day_of(user: dict) -> dict:
    return {k: user[k] for k in DEFAULT_DAY}


async def test_get_me_returns_the_account_and_the_default_day(sign_in):
    me = await sign_in()

    response = await me.client.get("/v1/me")

    assert response.status_code == 200
    user = response.json()
    assert (user["id"], user["email"], user["pursuer"]) == (
        str(me.user_id),
        me.email,
        "goose",
    )
    assert day_of(user) == DEFAULT_DAY
    assert user["pending"] is None
    assert user["created_at"] == "2026-11-26T15:00:00Z"


async def test_a_day_change_is_pending_until_the_next_day_starts(sign_in, clock):
    me = await sign_in()

    response = await me.client.patch("/v1/me", json={"day_end": "02:00"})

    assert response.status_code == 200
    assert day_of(response.json()) == DEFAULT_DAY
    assert response.json()["pending"] == {
        "effective_from": "2026-11-27",
        **DEFAULT_DAY,
        "day_end": "02:00",
    }
    assert (await me.client.get("/v1/me")).json() == response.json()

    # 05:59 on 2026-11-27: still the night after 2026-11-26.
    clock.set(datetime(2026, 11, 27, 10, 59, tzinfo=UTC))
    assert (await me.client.get("/v1/me")).json()["pending"] is not None

    clock.set(datetime(2026, 11, 27, 11, tzinfo=UTC))  # 06:00, the next day starts
    user = (await me.client.get("/v1/me")).json()
    assert day_of(user) == {**DEFAULT_DAY, "day_end": "02:00"}
    assert user["pending"] is None


async def test_a_change_during_the_night_waits_for_the_day_about_to_start(
    sign_in, clock
):
    me = await sign_in()
    clock.set(datetime(2026, 11, 27, 6, tzinfo=UTC))  # 01:00 on 2026-11-27

    user = (await me.client.patch("/v1/me", json={"day_start": "07:00"})).json()

    assert day_of(user) == DEFAULT_DAY
    assert user["pending"]["effective_from"] == "2026-11-27"


@pytest.mark.parametrize(
    "change",
    [{"day_start": "04:00"}, {"time_zone": "Europe/London"}],
    ids=["earlier start", "zone to the east"],
)
async def test_a_night_change_that_would_start_the_next_day_already_waits_a_day(
    sign_in, clock, change
):
    me = await sign_in()
    # 05:00 on 2026-11-27 in New York, the night after 2026-11-26. Under the new
    # settings 2026-11-27 would have started already, at 04:00 or at 01:00.
    clock.set(datetime(2026, 11, 27, 10, tzinfo=UTC))

    user = (await me.client.patch("/v1/me", json=change)).json()

    assert day_of(user) == DEFAULT_DAY
    assert user["pending"]["effective_from"] == "2026-11-28"
    clock.set(datetime(2026, 11, 27, 11, tzinfo=UTC))  # 06:00: 2026-11-27 starts
    assert day_of((await me.client.get("/v1/me")).json()) == DEFAULT_DAY


async def test_a_late_revert_keeps_the_day_about_to_start(sign_in, clock):
    me = await sign_in()
    clock.set(datetime(2026, 11, 27, 6, tzinfo=UTC))  # 01:00
    await me.client.patch("/v1/me", json={"day_start": "07:00"})
    # 06:30: under the old settings 2026-11-27 would have started at 06:00.
    clock.set(datetime(2026, 11, 27, 11, 30, tzinfo=UTC))

    reverted = (await me.client.patch("/v1/me", json={"day_start": "06:00"})).json()

    assert reverted["pending"]["effective_from"] == "2026-11-28"
    clock.set(datetime(2026, 11, 27, 12, tzinfo=UTC))  # 07:00: 2026-11-27 starts
    user = (await me.client.get("/v1/me")).json()
    assert user["day_start"] == "07:00"
    assert (user["pending"]["effective_from"], user["pending"]["day_start"]) == (
        "2026-11-28",
        "06:00",
    )


async def test_changes_on_one_day_merge_and_a_revert_clears_them(sign_in):
    me = await sign_in()

    await me.client.patch("/v1/me", json={"day_end": "02:00"})
    merged = await me.client.patch("/v1/me", json={"time_zone": "America/Los_Angeles"})

    assert merged.json()["pending"] == {
        "effective_from": "2026-11-27",
        "time_zone": "America/Los_Angeles",
        "day_start": "06:00",
        "day_end": "02:00",
    }
    reverted = await me.client.patch(
        "/v1/me", json={"time_zone": "America/New_York", "day_end": "00:00"}
    )
    assert reverted.json()["pending"] is None
    assert day_of(reverted.json()) == DEFAULT_DAY


@pytest.mark.parametrize(
    ("change", "fields"),
    [
        ({"day_start": "06:00", "day_end": "13:00"}, ["day_start", "day_end"]),
        ({"day_end": "13:59"}, ["day_end"]),
        ({"day_end": "05:00"}, ["day_end"]),
        ({"day_start": "06:00", "day_end": "06:00"}, ["day_start", "day_end"]),
        ({"time_zone": "Mars/Olympus"}, ["time_zone"]),
    ],
    ids=["seven hours", "just under eight", "twenty-three", "no night", "bad zone"],
)
async def test_a_day_outside_the_rules_is_refused(sign_in, change, fields):
    me = await sign_in()

    response = await me.client.patch("/v1/me", json=change)

    assert response.status_code == 422
    problem = response.json()
    assert problem["type"] == "invalid"
    assert [e["field"] for e in problem["errors"]] == fields
    assert (await me.client.get("/v1/me")).json()["pending"] is None


@pytest.mark.parametrize(
    ("day_start", "day_end"), [("06:00", "14:00"), ("06:00", "04:00")]
)
async def test_days_of_eight_and_twenty_two_hours_are_allowed(
    sign_in, day_start, day_end
):
    me = await sign_in()

    response = await me.client.patch(
        "/v1/me", json={"day_start": day_start, "day_end": day_end}
    )

    assert response.status_code == 200
    assert response.json()["pending"]["day_end"] == day_end


async def test_the_display_name_and_pursuer_change_now(sign_in, db, clock):
    me = await sign_in()
    later = datetime(2026, 11, 26, 16, tzinfo=UTC)
    clock.set(later)

    response = await me.client.patch(
        "/v1/me", json={"display_name": "Matt", "pursuer": "goose", "time_zone": None}
    )

    assert response.status_code == 200
    assert (response.json()["display_name"], response.json()["pending"]) == (
        "Matt",
        None,
    )
    # The pursuer is unchanged, and nothing else touches the chase.
    assert (
        await db.scalar(select(User.chase_changed_at).where(User.id == me.user_id))
        is None
    )
    refused = await me.client.patch("/v1/me", json={"pursuer": "pirate"})
    assert refused.status_code == 422


async def test_a_day_change_marks_the_chase_changed(sign_in, db, clock):
    me = await sign_in()
    later = datetime(2026, 11, 26, 16, tzinfo=UTC)
    clock.set(later)

    await me.client.patch("/v1/me", json={"day_start": "07:00"})

    assert (
        await db.scalar(select(User.chase_changed_at).where(User.id == me.user_id))
        == later
    )


TABLES_BY_USER = [
    "users WHERE id = :u",
    "day_settings WHERE user_id = :u",
    "habits WHERE user_id = :u",
    "habit_targets WHERE habit_id IN (SELECT id FROM habits WHERE user_id = :u)",
    "days WHERE user_id = :u",
    "logs WHERE user_id = :u",
    "sessions WHERE user_id = :u",
    "keys WHERE user_id = :u",
    "installations WHERE user_id = :u",
    "push_jobs WHERE user_id = :u",
    "push_deliveries WHERE user_id = :u",
]


async def counts(db, user_id: uuid.UUID) -> dict[str, int]:
    await db.rollback()
    return {
        t.split()[0]: await db.scalar(text(f"SELECT count(*) FROM {t}"), {"u": user_id})
        for t in TABLES_BY_USER
    }


class RecordingIdentityAdmin:
    def __init__(self) -> None:
        self.deleted: list[str] = []

    async def delete_identity(self, subject: str) -> None:
        self.deleted.append(subject)


async def test_deleting_the_account_removes_every_row_and_revokes_it(
    app, wired, sign_in, db
):
    admin = RecordingIdentityAdmin()
    app.state.wiring = dataclasses.replace(
        wired,
        accounts=AccountService(
            settings=wired.settings,
            clock=wired.clock,
            sessions=wired.sessions,
            identity_admin=admin,
        ),
    )
    me, other = await sign_in(), await sign_in()
    for user in (me, other):
        await fill_every_table(db, user.user_id)
    api_key = await builders.key(db, me.user_id, "api")
    await db.commit()
    assert 0 not in (await counts(db, me.user_id)).values()

    # An API key cannot delete the account.
    by_key = await me.client.delete(
        "/v1/me", headers={"Authorization": f"Bearer {api_key}"}
    )
    assert by_key.status_code == 401

    response = await me.client.delete("/v1/me")

    assert response.status_code == 204
    assert await counts(db, me.user_id) == dict.fromkeys(
        (t.split()[0] for t in TABLES_BY_USER), 0
    )
    assert 0 not in (await counts(db, other.user_id)).values()
    assert (await me.client.get("/v1/me")).status_code == 401
    assert len(admin.deleted) == 1


async def fill_every_table(db, user_id: uuid.UUID) -> None:
    habit = await builders.habit(db, user_id)
    await builders.log(db, user_id, habit.id)
    await builders.day(db, user_id)
    await builders.key(db, user_id, "mcp")
    now = builders.EXAMPLE_START
    await db.execute(
        text(
            "INSERT INTO installations (id, user_id, installation_id, environment,"
            " app_version, created_at, updated_at)"
            " VALUES (gen_random_uuid(), :u, 'phone', 'sandbox', '1.0', :t, :t);"
        ),
        {"u": user_id, "t": now},
    )
    await db.execute(
        text(
            "INSERT INTO push_jobs (id, user_id, date, kind, due_at, payload, attempts)"
            " VALUES (gen_random_uuid(), :u, '2026-11-26', 'lead', :t, '{}', 0)"
        ),
        {"u": user_id, "t": now},
    )
    await db.execute(
        text(
            "INSERT INTO push_deliveries (id, user_id, installation_id, payload,"
            " sent_at) VALUES (gen_random_uuid(), :u, 'phone', '{}', :t)"
        ),
        {"u": user_id, "t": now},
    )
