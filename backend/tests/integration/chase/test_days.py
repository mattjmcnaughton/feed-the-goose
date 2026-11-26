"""Days, settlement and history (TDD §5.3, §5.4, constitution §4).

The example day is 2026-11-26 in New York, 06:00 to 00:00 (11:00Z to 05:00Z), 18
hours at 100 / 18 steps an hour, with Pushups 50, Workout 30 and Reading 20. Expected
values are worked out by hand from those numbers.
"""

from datetime import UTC, date, datetime
from fractions import Fraction

import pytest

from tests.integration.chase.helpers import day_rows, log_body, three_habits
from tests.support import builders

pytestmark = pytest.mark.anyio


def at(stamp: str) -> datetime:
    return datetime.fromisoformat(stamp).astimezone(UTC)


async def test_a_user_with_no_habits_has_no_chase(sign_in, db):
    user = await sign_in()
    # A habit that starts tomorrow leaves today without a chase too.
    await builders.habit(db, user.user_id, effective_from=date(2026, 11, 27))
    await db.commit()

    response = await user.client.get("/v1/chase/today")

    assert response.status_code == 404
    assert response.json()["type"] == "no_chase"


async def test_a_log_that_arrives_late_undoes_a_catch_until_the_day_settles(
    sign_in, db, clock
):
    """A starting lead of 250/3 is caught after 15 hours, at 21:00 local (02:00Z).
    Pushups 50 logged at 20:00 (01:00Z) earns 100/3, which moves the catch to 21
    hours, past the day's end."""
    late, settled = await sign_in(), await sign_in()
    for user in (late, settled):
        await builders.day(db, user.user_id, starting_lead=Fraction(250, 3))
    (pushups, *_), (their_pushups, *_) = (
        await three_habits(db, late.user_id),
        await three_habits(db, settled.user_id),
    )
    clock.set(at("2026-11-27T04:00:00Z"))  # 23:00 local

    before = await late.client.get("/v1/chase/today")
    logged = await late.client.post(
        "/v1/logs", json=log_body(pushups.id, "2026-11-27T01:00:00Z", amount=50)
    )

    assert (before.json()["state"], before.json()["caught_at"]) == (
        "caught",
        "2026-11-27T02:00:00Z",
    )
    assert logged.status_code == 201
    chase = logged.json()["chase"]
    # 250/3 + 100/3 - 17 hours x 100/18 = 200/9
    assert (chase["state"], chase["lead"], chase["caught_at"]) == (
        "running",
        22.2,
        None,
    )
    assert logged.json()["event"] == {
        "kind": "gain",
        "habit_id": str(pushups.id),
        "steps": 33.3,
    }

    # The same log, first sent once the next day has started at 11:00Z.
    clock.set(at("2026-11-27T12:00:00Z"))
    too_late = await settled.client.post(
        "/v1/logs", json=log_body(their_pushups.id, "2026-11-27T01:00:00Z", amount=50)
    )

    assert too_late.status_code == 409
    assert too_late.json()["type"] == "day_settled"


async def test_a_user_away_for_three_days_has_them_settled_by_one_request(
    sign_in, db, clock
):
    user = await sign_in()
    pushups, workout, reading = await three_habits(db, user.user_id)
    # 2026-11-26: every habit done by 14:00 local, so complete with the lead frozen
    # at 100 + 100 - 8 hours x 100/18 = 155.6.
    for habit, amount, stamp in [
        (pushups, 50, "2026-11-26T13:00:00Z"),
        (workout, 30, "2026-11-26T15:00:00Z"),
        (reading, 20, "2026-11-26T19:00:00Z"),
    ]:
        await builders.log(
            db, user.user_id, habit.id, amount=amount, logged_at=at(stamp)
        )
    # 2026-11-27: only Pushups, so short with 100 + 100/3 - 100 = 33.3 carried.
    await builders.log(
        db,
        user.user_id,
        pushups.id,
        amount=50,
        logged_at=at("2026-11-27T17:00:00Z"),
        day=date(2026, 11, 27),
    )
    # 2026-11-28: nothing, so 33.3 runs out after 6 hours, at 12:00 local (17:00Z).
    await db.commit()
    clock.set(at("2026-11-29T15:00:00Z"))

    today = await user.client.get("/v1/chase/today")
    rows = await day_rows(db, user.user_id)

    assert [
        (r["date"], r["result"], r["end_lead"], r["streak_after"], r["caught_at"])
        for r in rows
    ] == [
        (date(2026, 11, 26), "complete", Fraction(1400, 9), 1, None),
        (date(2026, 11, 27), "short", Fraction(100, 3), 1, None),
        (date(2026, 11, 28), "caught", Fraction(0), 0, at("2026-11-28T17:00:00Z")),
        (date(2026, 11, 29), None, None, None, None),
    ]
    assert [r["starting_lead"] for r in rows] == [100, 100, Fraction(100, 3), 100]
    assert {r["settled_at"] for r in rows[:3]} == {clock.now()}
    assert today.json()["date"] == "2026-11-29"
    assert today.json()["streak"] == {"complete_days": 0, "stage": 0}

    history = await user.client.get(
        "/v1/days", params={"from": "2026-11-25", "to": "2026-11-29"}
    )

    assert [
        (d["date"], d["result"], d["end_lead"], d["complete_days"])
        for d in history.json()
    ] == [
        ("2026-11-26", "complete", 155.6, 1),
        ("2026-11-27", "short", 33.3, 1),
        ("2026-11-28", "caught", 0.0, 0),
        ("2026-11-29", "running", None, 0),
    ]


@pytest.mark.parametrize(
    "archived_from",
    [None, date(2026, 11, 27)],
    ids=["days-continue", "no-later-day"],
)
async def test_a_settled_day_is_unchanged_by_later_requests(
    sign_in, db, clock, archived_from
):
    """With the habits archived from the next date, the settled day stays the
    user's latest day, the case where settlement could be run again."""
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id, archived_from=archived_from)
    body = log_body(pushups.id, "2026-11-26T14:00:00Z")
    await user.client.post("/v1/logs", json=body)
    clock.set(at("2026-11-27T12:00:00Z"))
    await user.client.get("/v1/chase/today")
    settled = (await day_rows(db, user.user_id))[0]

    responses = [
        await user.client.post(
            "/v1/logs", json=log_body(pushups.id, "2026-11-26T20:00:00Z")
        ),
        await user.client.delete(f"/v1/logs/{body['id']}"),
        await user.client.post("/v1/logs", json=body),
        await user.client.get(
            "/v1/days", params={"from": "2026-11-26", "to": "2026-11-27"}
        ),
        await user.client.get("/v1/logs", params={"date": "2026-11-26"}),
    ]
    clock.set(at("2026-11-30T12:00:00Z"))
    await user.client.get("/v1/chase/today")
    after = (await day_rows(db, user.user_id))[0]

    assert [r.status_code for r in responses] == [409, 409, 200, 200, 200]
    assert settled["settled_at"] == at("2026-11-27T12:00:00Z")
    # 100 + 20/3 - 100: short, with the log's steps carried.
    assert (settled["result"], settled["end_lead"]) == ("short", Fraction(20, 3))
    assert after == settled


async def test_the_first_day_starts_when_the_first_habit_is_created(sign_in, db, clock):
    """Case 18: the first habit is created at 20:00 local, so the pursuer walks 4
    hours at 100/18 an hour, 22.2 steps, and the day ends short with 77.8."""
    user = await sign_in()
    habit = await builders.habit(db, user.user_id)
    habit.created_at = at("2026-11-27T01:00:00Z")
    await db.commit()
    clock.set(at("2026-11-27T05:00:00Z"))  # 00:00 local, the day's end

    chase = (await user.client.get("/v1/chase/today")).json()

    assert chase["day_starts_at"] == "2026-11-27T01:00:00Z"
    assert (chase["state"], chase["walked"], chase["lead"]) == ("short", 22.2, 77.8)
    assert chase["steps_per_hour"] == 5.56
    assert chase["next_day_starts_at"] == "2026-11-27T11:00:00Z"


async def test_a_complete_day_counts_in_the_streak_until_it_is_undone(
    sign_in, db, clock
):
    user = await sign_in()
    pushups, workout, reading = await three_habits(db, user.user_id)
    for habit, amount in [(pushups, 50), (workout, 30)]:
        await builders.log(db, user.user_id, habit.id, amount=amount)
    await db.commit()
    finishing = log_body(reading.id, "2026-11-26T14:30:00Z", amount=20)

    complete = await user.client.post("/v1/logs", json=finishing)
    undone = await user.client.delete(f"/v1/logs/{finishing['id']}")

    assert complete.json()["event"]["kind"] == "complete"
    assert complete.json()["chase"]["state"] == "complete"
    assert complete.json()["chase"]["streak"] == {"complete_days": 1, "stage": 0}
    assert undone.json()["chase"]["state"] == "running"
    assert undone.json()["chase"]["streak"] == {"complete_days": 0, "stage": 0}


async def test_days_from_after_to_are_invalid(sign_in):
    user = await sign_in()

    response = await user.client.get(
        "/v1/days", params={"from": "2026-11-26", "to": "2026-11-25"}
    )

    assert response.status_code == 422
    assert response.json()["type"] == "invalid"


async def test_a_first_habit_created_during_the_night_starts_the_next_day(
    sign_in, db, clock
):
    """Created at 01:00 on 2026-11-27, after the 2026-11-26 day it belongs to has
    ended, so the first day is 2026-11-27 and the night has no day."""
    user = await sign_in()
    habit = await builders.habit(db, user.user_id)
    habit.created_at = at("2026-11-27T06:00:00Z")
    await db.commit()
    clock.set(at("2026-11-27T06:20:00Z"))

    night = await user.client.post(
        "/v1/logs", json=log_body(habit.id, "2026-11-27T06:20:00Z", amount=50)
    )
    clock.set(at("2026-11-27T12:00:00Z"))
    today = await user.client.get("/v1/chase/today")

    assert night.status_code == 422
    assert (today.json()["date"], today.json()["day_starts_at"]) == (
        "2026-11-27",
        "2026-11-27T11:00:00Z",
    )
    assert [r["date"] for r in await day_rows(db, user.user_id)] == [date(2026, 11, 27)]


async def test_a_date_with_no_habits_has_no_day_and_the_lead_carries_over_it(
    sign_in, db, clock
):
    """Pushups 10 of 50 on 2026-11-26 ends short with 100 + 20 - 100 = 20. The
    habit is archived from 2026-11-27, and another starts on 2026-11-28."""
    user = await sign_in()
    pushups = await builders.habit(db, user.user_id, archived_from=date(2026, 11, 27))
    await builders.habit(
        db, user.user_id, name="Reading", effective_from=date(2026, 11, 28)
    )
    await builders.log(db, user.user_id, pushups.id, amount=10)
    await db.commit()

    clock.set(at("2026-11-27T15:00:00Z"))
    gap = await user.client.get("/v1/chase/today")
    clock.set(at("2026-11-28T15:00:00Z"))
    after = await user.client.get("/v1/chase/today")

    assert gap.status_code == 404
    assert gap.json()["type"] == "no_chase"
    assert [r["date"] for r in await day_rows(db, user.user_id)] == [
        date(2026, 11, 26),
        date(2026, 11, 28),
    ]
    assert (after.json()["starting_lead"], after.json()["day_starts_at"]) == (
        20.0,
        "2026-11-28T11:00:00Z",
    )


async def test_a_target_change_leaves_todays_chase_unchanged(sign_in, db, clock):
    """Pushups 20 of 50 earns 2/5 of a third of 100 steps, 13.3. Raising the
    target to 100 at noon applies from tomorrow."""
    user = await sign_in()
    pushups, *_ = await three_habits(db, user.user_id)
    await user.client.post(
        "/v1/logs", json=log_body(pushups.id, "2026-11-26T14:00:00Z", amount=20)
    )
    before = (await user.client.get("/v1/chase/today")).json()
    clock.set(at("2026-11-26T17:00:00Z"))

    patched = await user.client.patch(f"/v1/habits/{pushups.id}", json={"target": 100})
    today = (await user.client.get("/v1/chase/today")).json()
    clock.set(at("2026-11-27T15:00:00Z"))
    tomorrow = (await user.client.get("/v1/chase/today")).json()

    assert patched.status_code == 200, patched.text
    assert before["habits"][0] == today["habits"][0]
    assert (today["habits"][0]["target"], today["habits"][0]["steps"]) == (50, 13.3)
    assert today["earned"] == before["earned"] == 13.3
    assert tomorrow["habits"][0]["target"] == 100
