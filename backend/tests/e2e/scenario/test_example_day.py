"""The example day: the shared fixtures replayed against the served app (TDD §7).

A user with the fixtures' three habits and a streak of 13 logs, retries, undoes and
reads through the day. Each exchange runs with the clock at the time its response
was taken, and must answer the fixture's status and body exactly.
"""

import json
from datetime import UTC, date, datetime, timedelta
from fractions import Fraction
from pathlib import Path
from uuid import UUID

import httpx
import pytest

from feed_the_goose.models import Day, Habit
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.repositories.habits import HabitRepository

pytestmark = pytest.mark.anyio

FIXTURES = Path(__file__).resolve().parents[4] / "clients" / "fixtures"
EXCHANGES = [
    "example-day-01-log-pushups",
    "example-day-02-log-workout",
    "example-day-03-retry-log-pushups",
    "example-day-04-log-pushups",
    "example-day-05-log-reading",
    "example-day-06-undo-reading",
    "example-day-07-chase",
    "example-day-08-logs",
    "days-list",
    "error-day-settled",
]
HABITS = [  # The fixtures' habits: ID suffix, name, unit, target, chunk.
    (1, "Pushups", "reps", 50, 10),
    (2, "Workout", "minutes", 30, 10),
    (3, "Reading", "pages", 20, 5),
]
# The end leads of the settled days in `days-list`; earlier days are arbitrary.
END_LEADS = {
    date(2026, 11, 20): "131.5",
    date(2026, 11, 21): "128.9",
    date(2026, 11, 22): "140.2",
    date(2026, 11, 23): "125.0",
    date(2026, 11, 24): "133.8",
    date(2026, 11, 25): "137.4",
}
EMAIL = "example-day@example.com"


async def _seed(db, user_id: UUID) -> None:
    """The habits, and 13 complete days from 2026-11-13 to 2026-11-25."""
    habits = HabitRepository(db)
    for position, (n, name, unit, target, chunk) in enumerate(HABITS):
        await habits.add(
            Habit(
                id=UUID(f"22222222-2222-4222-8222-{n:012d}"),
                user_id=user_id,
                name=name,
                unit=unit,
                chunk=chunk,
                position=position,
                effective_from=date(2026, 11, 1),
                archived_from=None,
                created_at=datetime(2026, 11, 1, 11, tzinfo=UTC),
            ),
            target,
        )
    for streak in range(1, 14):
        on = date(2026, 11, 12) + timedelta(days=streak)
        starts_at = datetime.combine(on, datetime.min.time(), UTC) + timedelta(hours=11)
        await DayRepository(db).add(
            Day(
                user_id=user_id,
                date=on,
                starts_at=starts_at,
                ends_at=starts_at + timedelta(hours=18),
                starting_lead=Fraction(100),
                result="complete",
                end_lead=Fraction(END_LEADS.get(on, "120")),
                caught_at=None,
                streak_after=streak,
                settled_at=starts_at + timedelta(days=1),
            )
        )
    await db.commit()


def _as_of(body: object) -> datetime | None:
    if isinstance(body, dict):
        stamp = body.get("as_of") or body.get("chase", {}).get("as_of")
        return datetime.fromisoformat(stamp) if stamp else None
    return None


async def test_the_fixtures_replay_against_the_served_app(
    base_url, clock, settings, db
):
    clock.set(datetime(2026, 11, 26, 14, tzinfo=UTC))
    settings.allowed_emails = (EMAIL,)
    async with httpx.AsyncClient(base_url=base_url) as http:
        token = (await http.post("/dev/token", json={"email": EMAIL})).json()
        session = await http.post(
            "/v1/auth/session",
            json={
                "auth0_access_token": token["identity_token"],
                "time_zone": "America/New_York",
                "device_name": "Scenario",
            },
        )
        assert session.status_code == 201, session.text
        user_id = UUID(session.json()["user"]["id"])
        await _seed(db, user_id)
        http.headers["Authorization"] = f"Bearer {session.json()['session_token']}"

        for name in EXCHANGES:
            fixture = json.loads((FIXTURES / f"{name}.json").read_text())
            request, expected = fixture["request"], fixture["response"]
            if (at := _as_of(expected["body"])) is not None:
                clock.set(at)

            response = await http.request(
                request["method"], request["path"], json=request["body"]
            )

            assert (response.status_code, response.json()) == (
                expected["status"],
                expected["body"],
            ), name
