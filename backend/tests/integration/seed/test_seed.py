"""`POST /dev/seed` and its four scenarios (TDD §5.10).

Each test seeds a user, signs in as them through the dev sign-in, and checks what the
chase routes return. The expected values come from TDD §5.10: the demo's lead of 80 is
100 + 46.7 earned (Pushups 20 of 50 and Workout 30 of 30, a third each) − 66.7 walked
(two thirds of the day).
"""

from collections import Counter
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest

from feed_the_goose import wiring
from feed_the_goose.app import create_app
from feed_the_goose.config import Settings

pytestmark = pytest.mark.anyio


async def seed(client, scenario: str, email: str, **extra) -> dict:
    response = await client.post(
        "/dev/seed", json={"scenario": scenario, "email": email, **extra}
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize(
    "now",
    [
        datetime(2026, 11, 26, 15, tzinfo=UTC),  # 10:00 in New York
        # 01:30 in New York the morning the clocks went forward, so the day under
        # way started the evening before and the history crosses the change.
        datetime(2026, 3, 8, 6, 30, tzinfo=UTC),
    ],
)
async def test_demo_is_two_thirds_through_a_day_with_a_streak_of_13(
    client, sign_in, clock, now
):
    clock.set(now)
    seeded = await seed(client, "demo", "Demo@Example.com")
    user = await sign_in("demo@example.com")

    chase = (await user.client.get("/v1/chase/today")).json()
    today = date.fromisoformat(chase["date"])
    history = (
        await user.client.get(
            "/v1/days",
            params={
                "from": str(today - timedelta(days=40)),
                "to": str(today - timedelta(days=1)),
            },
        )
    ).json()

    assert seeded == {"email": "demo@example.com", "handle": "matt"}
    assert chase["state"] == "running"
    assert chase["lead"] == pytest.approx(80, abs=0.5)
    assert chase["streak"] == {"complete_days": 13, "stage": 2}
    assert [(h["name"], h["logged"], h["target"]) for h in chase["habits"]] == [
        ("Pushups", 20, 50),
        ("Workout", 30, 30),
        ("Reading", 0, 20),
    ]
    assert len(history) == 34
    assert Counter(d["result"] for d in history) == {
        "complete": 31,
        "short": 2,
        "caught": 1,
    }
    caught = next(d for d in history if d["result"] == "caught")
    assert date.fromisoformat(caught["date"]) == today - timedelta(days=14)
    assert history[-1]["complete_days"] == 13


async def test_caught_soon_is_caught_after_the_delay(client, sign_in, clock):
    seeded_at = clock.now()
    await seed(client, "caught-soon", "late@example.com", delay_seconds=5)
    user = await sign_in("late@example.com")

    first = (await user.client.get("/v1/chase/today")).json()
    clock.set(seeded_at + timedelta(seconds=6))
    later = (await user.client.get("/v1/chase/today")).json()
    yesterday = (
        await user.client.get(
            "/v1/days",
            params={"from": "2000-01-01", "to": str(date.fromisoformat(first["date"]))},
        )
    ).json()[0]

    assert first["state"] == "running"
    assert datetime.fromisoformat(first["caught_at"]) == seeded_at + timedelta(
        seconds=5
    )
    assert later["state"] == "caught"
    assert yesterday["result"] == "short"
    assert yesterday["end_lead"] == pytest.approx(first["starting_lead"], abs=0.1)


async def test_almost_complete_leaves_one_chunk_on_each_habit(client, sign_in):
    await seed(client, "almost-complete", "close@example.com")
    user = await sign_in("close@example.com")

    chase = (await user.client.get("/v1/chase/today")).json()

    assert chase["state"] == "running"
    assert len(chase["habits"]) == 3
    assert all(h["target"] - h["logged"] == h["chunk"] for h in chase["habits"])


async def test_fresh_has_no_chase(client, sign_in):
    seeded = await seed(client, "fresh", "new@example.com")
    user = await sign_in("new@example.com")

    response = await user.client.get("/v1/chase/today")

    assert seeded == {"email": "new@example.com", "handle": None}
    assert response.status_code == 404
    assert response.json()["type"] == "no_chase"


async def test_seeding_an_email_again_resets_that_user(client, sign_in):
    await seed(client, "demo", "again@example.com")
    first = await sign_in("again@example.com")
    await seed(client, "fresh", "again@example.com")

    stale = await first.client.get("/v1/chase/today")
    second = await sign_in("again@example.com")
    response = await second.client.get("/v1/chase/today")

    assert stale.status_code == 401
    assert second.user_id != first.user_id
    assert response.status_code == 404


async def test_the_demo_handle_moves_to_the_latest_demo_user(client):
    await seed(client, "demo", "one@example.com")

    assert (await seed(client, "demo", "two@example.com"))["handle"] == "matt"


async def test_an_unknown_scenario_is_invalid(client):
    response = await client.post(
        "/dev/seed", json={"scenario": "nope", "email": "x@example.com"}
    )

    assert response.status_code == 422


async def test_production_has_no_seed_route():
    app = create_app(wiring.build(Settings(_env_file=None, env="production")))

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        response = await c.post(
            "/dev/seed", json={"scenario": "demo", "email": "matt@example.com"}
        )

    assert response.status_code == 404
