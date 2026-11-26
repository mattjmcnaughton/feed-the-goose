"""The public profile (TDD §5.8, constitution §5, PRD S12).

The expected values come from TDD §5.10's demo scenario: a streak of 13 at stage 2, a
lead of 80 two thirds through the day, and 34 settled days (31 complete, 2 short, 1
caught) before today.
"""

import re
import uuid
from collections import Counter
from datetime import datetime, timedelta

import pytest

pytestmark = pytest.mark.anyio

# The fields named for publication. Adding a field to the profile fails this list.
PUBLISHED = {
    "display_name",
    "pursuer",
    "complete_days",
    "stage",
    "state",
    "lead",
    "as_of",
    "steps_per_hour",
    "caught_at",
    "days",
}
# The seed's habits and units, and the demo's logged and target amounts.
PRIVATE_WORDS = ["Pushups", "Workout", "Reading", "reps", "minutes", "pages"]
PRIVATE_AMOUNTS = ["20 of 50", "30 of 30", "0 of 20", "20/50", "30/30", "0/20"]


async def seed(client, scenario: str, email: str, **extra) -> dict:
    response = await client.post(
        "/dev/seed", json={"scenario": scenario, "email": email, **extra}
    )
    assert response.status_code == 200, response.text
    return response.json()


def visible_text(html: str) -> str:
    html = re.sub(r"<style>.*?</style>", " ", html, flags=re.S)
    return re.sub(r"<[^>]+>", " ", html)


def assert_public_headers(response) -> None:
    assert response.headers["cache-control"] == "no-store"
    assert "set-cookie" not in response.headers


async def publish(user, handle: str) -> None:
    response = await user.client.put(
        "/v1/me/profile", json={"handle": handle, "public": True}
    )
    assert response.status_code == 200, response.text


async def test_the_json_has_exactly_the_published_fields(client):
    await seed(client, "demo", "demo@example.com")

    response = await client.get("/v1/profiles/matt")
    body = response.json()

    assert response.status_code == 200
    assert_public_headers(response)
    assert set(body) == PUBLISHED
    assert set(body["days"][0]) == {"date", "result"}
    assert body["display_name"] == "Matt"
    assert body["state"] == "running"
    assert body["lead"] == pytest.approx(80, abs=0.5)
    assert (body["complete_days"], body["stage"]) == (13, 2)
    # 80 steps at 100 per 18 hours lasts 14.4 hours, past the 6 hours left.
    assert body["caught_at"] is None
    assert len(body["days"]) == 35
    assert body["days"][-1]["result"] == "running"
    assert Counter(d["result"] for d in body["days"][:-1]) == {
        "complete": 31,
        "short": 2,
        "caught": 1,
    }


async def test_the_page_shows_no_habit_names_units_or_amounts(client):
    await seed(client, "demo", "demo@example.com")

    response = await client.get("/matt")
    html = response.text
    text = visible_text(html)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert_public_headers(response)
    assert "Matt" in text
    assert "13 days running" in text
    assert "80 steps behind Matt" in text
    for word in PRIVATE_WORDS:
        assert word.lower() not in html.lower(), word
    for amount in PRIVATE_AMOUNTS:
        assert amount not in text, amount


@pytest.mark.parametrize("path", ["/v1/profiles/{}", "/{}"])
async def test_a_private_or_unknown_profile_is_not_found(client, sign_in, path):
    user = await sign_in()
    await user.client.put("/v1/me/profile", json={"handle": "hidden", "public": False})

    for handle in ["hidden", "nobody-here"]:
        response = await client.get(path.format(handle))
        assert response.status_code == 404
        assert_public_headers(response)


async def test_unpublishing_hides_the_profile_at_once(client, sign_in):
    await seed(client, "demo", "demo@example.com")
    user = await sign_in("demo@example.com")
    assert (await client.get("/matt")).status_code == 200

    response = await user.client.put(
        "/v1/me/profile", json={"handle": "matt", "public": False}
    )

    assert response.json() == {"handle": "matt", "public": False}
    assert (await client.get("/matt")).status_code == 404
    assert (await client.get("/v1/profiles/matt")).status_code == 404


async def test_a_public_read_ignores_credentials(client, sign_in):
    await seed(client, "demo", "demo@example.com")
    other = await sign_in()

    response = await other.client.get("/v1/profiles/matt")

    assert response.status_code == 200
    assert response.json()["display_name"] == "Matt"
    assert_public_headers(response)


async def test_a_display_name_is_shown_as_text(client, sign_in):
    await seed(client, "almost-complete", "xss@example.com")
    user = await sign_in("xss@example.com")
    await user.client.patch(
        "/v1/me", json={"display_name": "<script>alert(1)</script>"}
    )
    await publish(user, "xss")

    html = (await client.get("/xss")).text

    assert "<script>" not in html
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html


async def test_a_complete_day_shows_the_streak_including_today(client, sign_in):
    await seed(client, "almost-complete", "close@example.com")
    user = await sign_in("close@example.com")
    await publish(user, "close")
    chase = (await user.client.get("/v1/chase/today")).json()
    for habit in chase["habits"]:
        response = await user.client.post(
            "/v1/logs",
            json={
                "id": str(uuid.uuid4()),
                "habit_id": habit["habit_id"],
                "amount": habit["target"] - habit["logged"],
                "logged_at": chase["as_of"],
                "source": "app",
            },
        )
        assert response.status_code in (200, 201), response.text

    profile = (await client.get("/v1/profiles/close")).json()

    assert profile["state"] == "complete"
    assert profile["days"][-1]["result"] == "complete"
    assert profile["complete_days"] == chase["streak"]["complete_days"] + 1


async def test_a_caught_day_shows_when_the_catch_came(client, sign_in, clock):
    seeded_at = clock.now()
    await seed(client, "caught-soon", "late@example.com", delay_seconds=5)
    user = await sign_in("late@example.com")
    await publish(user, "late")

    before = (await client.get("/v1/profiles/late")).json()
    clock.set(seeded_at + timedelta(seconds=6))
    after = (await client.get("/v1/profiles/late")).json()
    page = visible_text((await client.get("/late")).text)

    assert before["state"] == "running"
    assert datetime.fromisoformat(before["caught_at"]) == seeded_at + timedelta(
        seconds=5
    )
    assert after["state"] == "caught"
    assert after["caught_at"] == before["caught_at"]
    assert after["days"][-1]["result"] == "caught"
    assert after["complete_days"] == 0
    # No complete day came before the catch, so no run ended.
    assert "The goose got late today" in page


async def test_a_handle_someone_else_holds_is_taken(client, sign_in):
    first, second = await sign_in(), await sign_in()
    await publish(first, "shared")

    response = await second.client.put(
        "/v1/me/profile", json={"handle": "shared", "public": True}
    )
    again = await first.client.put(
        "/v1/me/profile", json={"handle": "shared", "public": False}
    )

    assert response.status_code == 409
    assert response.json()["type"] == "handle_taken"
    assert again.json() == {"handle": "shared", "public": False}
    assert (await second.client.get("/v1/me/profile")).json() == {
        "handle": None,
        "public": False,
    }


@pytest.mark.parametrize(
    "handle", ["v1", "mcp", "dev", "healthz", "readyz", "docs", "ab", "Matt", "a_b"]
)
async def test_reserved_and_malformed_handles_are_invalid(sign_in, handle):
    user = await sign_in()

    response = await user.client.put(
        "/v1/me/profile", json={"handle": handle, "public": True}
    )

    assert response.status_code == 422
    assert response.json()["type"] == "invalid"


async def test_the_page_does_not_shadow_other_routes(client):
    assert (await client.get("/healthz")).status_code == 200
    assert (await client.get("/openapi.json")).status_code == 200
