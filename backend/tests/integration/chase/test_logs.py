"""Logs: idempotency, undo, and which logs are accepted (TDD §5.5, constitution §3).

The clock is 10:00 in New York on 2026-11-26, four hours into an 06:00 to 00:00 day.
"""

import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select

from feed_the_goose.models import Log, User
from tests.integration.chase.helpers import log_body, three_habits
from tests.support import builders

pytestmark = pytest.mark.anyio


async def test_twenty_concurrent_posts_with_one_id_store_one_log(sign_in, db):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")

    responses = await asyncio.gather(
        *(user.client.post("/v1/logs", json=body) for _ in range(20))
    )

    statuses = sorted(r.status_code for r in responses)
    assert statuses == [200] * 19 + [201]
    rows = await db.scalar(select(func.count()).where(Log.id == UUID(body["id"])))
    assert rows == 1
    # Every answer is the same log with the same event: 10 of 50 pushups is
    # a fifth of a third of 100 steps.
    assert {
        (r.json()["log"]["steps"], r.json()["event"]["kind"]) for r in responses
    } == {(6.7, "gain")}


async def test_a_repeated_id_ignores_the_new_fields(sign_in, db):
    user = await sign_in()
    pushups, workout, _ = await three_habits(db, user.user_id)
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")
    await user.client.post("/v1/logs", json=body)

    again = await user.client.post(
        "/v1/logs",
        json={**body, "habit_id": str(workout.id), "amount": 30},
    )

    assert again.status_code == 200
    assert again.json()["log"]["habit_id"] == str(pushups.id)
    assert again.json()["log"]["amount"] == 10
    assert again.json()["chase"]["earned"] == 6.7


async def test_an_undone_log_stays_undone_when_its_id_is_sent_again(sign_in, db, clock):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")
    await user.client.post("/v1/logs", json=body)
    undone = await user.client.delete(f"/v1/logs/{body['id']}")

    again = await user.client.post("/v1/logs", json=body)

    assert undone.status_code == 200
    assert again.status_code == 200
    log = again.json()["log"]
    assert log["undone_at"] == "2026-11-26T15:00:00Z"
    assert log["steps"] == 0.0
    assert again.json()["event"] == {
        "kind": "undone",
        "habit_id": str(pushups.id),
        "steps": 6.7,
    }
    assert again.json()["chase"]["earned"] == 0.0


async def test_undoing_twice_gives_the_same_result(sign_in, db, clock):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")
    await user.client.post("/v1/logs", json=body)
    first = await user.client.delete(f"/v1/logs/{body['id']}")

    second = await user.client.delete(f"/v1/logs/{body['id']}")

    assert second.status_code == 200
    assert second.json() == first.json()


async def test_another_users_log_id_is_invalid_and_cannot_be_undone(sign_in, db):
    owner, other = await sign_in(), await sign_in()
    (pushups, *_), (their_pushups, *_) = (
        await three_habits(db, owner.user_id),
        await three_habits(db, other.user_id),
    )
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")
    await owner.client.post("/v1/logs", json=body)

    reused = await other.client.post(
        "/v1/logs", json={**body, "habit_id": str(their_pushups.id)}
    )
    undo = await other.client.delete(f"/v1/logs/{body['id']}")

    assert reused.status_code == 422
    assert reused.json()["errors"] == [{"field": "id", "message": "Value is not valid"}]
    assert undo.status_code == 404


async def test_another_users_habit_is_not_found(sign_in, db):
    owner, other = await sign_in(), await sign_in()
    pushups, *_ = await three_habits(db, owner.user_id)
    await three_habits(db, other.user_id)

    response = await other.client.post(
        "/v1/logs", json=log_body(pushups.id, "2026-11-26T14:00:00Z")
    )

    assert response.status_code == 404
    assert response.json()["type"] == "not_found"


@pytest.mark.parametrize(
    ("logged_at", "status"),
    [
        ("2026-11-26T15:02:00Z", 201),  # arrival plus the 2 minutes of skew
        ("2026-11-26T15:02:01Z", 422),
    ],
)
async def test_a_log_may_be_up_to_two_minutes_ahead_of_its_arrival(
    sign_in, db, logged_at, status
):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)

    response = await user.client.post("/v1/logs", json=log_body(pushups.id, logged_at))

    assert response.status_code == status, response.text


async def test_a_log_for_a_habit_not_in_its_day_is_invalid(sign_in, db):
    user = await sign_in()
    await three_habits(db, user.user_id)
    tomorrows = await builders.habit(
        db, user.user_id, name="Stretch", position=3, effective_from=date(2026, 11, 27)
    )
    await db.commit()

    response = await user.client.post(
        "/v1/logs", json=log_body(tomorrows.id, "2026-11-26T14:00:00Z")
    )

    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "habit_id"


async def test_a_log_before_the_first_day_is_invalid(sign_in, db):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)

    # 05:00 in New York, before the day's 06:00 start: it belongs to 2026-11-25,
    # which has no habits.
    response = await user.client.post(
        "/v1/logs", json=log_body(pushups.id, "2026-11-26T10:00:00Z")
    )

    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "logged_at"


async def test_amount_defaults_to_the_habits_chunk(sign_in, db):
    user = await sign_in()
    _, _, reading = await three_habits(db, user.user_id)

    response = await user.client.post(
        "/v1/logs", json=log_body(reading.id, "2026-11-26T14:00:00Z", amount=None)
    )

    # 5 of 20 pages is a quarter of a third of 100 steps.
    assert response.json()["log"]["amount"] == 5
    assert response.json()["event"]["steps"] == 8.3


async def test_writes_that_change_the_chase_mark_it_changed_and_reads_do_not(
    sign_in, db, clock
):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)

    async def changed_at():
        await db.commit()
        return await db.scalar(
            select(User.chase_changed_at).where(User.id == user.user_id)
        )

    await user.client.get("/v1/chase/today")
    after_read = await changed_at()
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")
    await user.client.post("/v1/logs", json=body)
    after_log = await changed_at()
    clock.set(builders.EXAMPLE_START + timedelta(hours=5))
    await user.client.post("/v1/logs", json=body)
    after_replay = await changed_at()
    await user.client.delete(f"/v1/logs/{body['id']}")
    after_undo = await changed_at()

    assert after_read is None
    assert after_log == builders.EXAMPLE_START + timedelta(hours=4)
    assert after_replay == after_log
    assert after_undo == builders.EXAMPLE_START + timedelta(hours=5)


async def test_a_days_logs_are_newest_first_with_undone_ones(sign_in, db):
    user = await sign_in()
    pushups, workout, _ = await three_habits(db, user.user_id)
    first = log_body(pushups.id, "2026-11-26T12:00:00Z", log_id=uuid4())
    second = log_body(workout.id, "2026-11-26T13:00:00Z", amount=30)
    await user.client.post("/v1/logs", json=first)
    await user.client.post("/v1/logs", json=second)
    await user.client.delete(f"/v1/logs/{second['id']}")

    response = await user.client.get("/v1/logs", params={"date": "2026-11-26"})
    empty = await user.client.get("/v1/logs", params={"date": "2026-11-20"})

    assert [(log["id"], log["steps"]) for log in response.json()] == [
        (second["id"], 0.0),
        (first["id"], 6.7),
    ]
    assert response.json()[0]["undone_at"] is not None
    assert empty.json() == []


async def test_a_log_ahead_of_the_server_clock_counts_in_the_chase_it_returns(
    sign_in, db
):
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)

    response = await user.client.post(
        "/v1/logs", json=log_body(pushups.id, "2026-11-26T15:01:00Z")
    )

    chase = response.json()["chase"]
    assert (chase["earned"], chase["habits"][0]["logged"]) == (6.7, 10)


async def test_a_log_ahead_of_the_server_clock_may_fall_in_the_next_day(
    sign_in, db, clock
):
    """05:59:30 in New York, with the next day starting at 06:00."""
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)
    clock.set(datetime(2026, 11, 27, 10, 59, 30, tzinfo=UTC))

    response = await user.client.post(
        "/v1/logs", json=log_body(pushups.id, "2026-11-27T11:00:30Z")
    )

    assert response.status_code == 201, response.text
    assert response.json()["log"]["date"] == "2026-11-27"
    assert response.json()["chase"]["date"] == "2026-11-27"


async def test_a_log_just_before_the_first_habit_was_created_counts(sign_in, db):
    """A phone's clock may run behind the server's, so a log made right after the
    first habit was created can be stamped a moment before it."""
    user = await sign_in()
    habit = await builders.habit(db, user.user_id)
    habit.created_at = datetime(2026, 11, 26, 14, 59, 59, 600000, tzinfo=UTC)
    await db.commit()

    response = await user.client.post(
        "/v1/logs", json=log_body(habit.id, "2026-11-26T14:59:59Z")
    )

    assert response.status_code == 201, response.text
    assert response.json()["chase"]["earned"] == 20.0
