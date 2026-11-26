"""Habits (API spec "Habits", constitution §4).

The clock is 10:00 in New York on 2026-11-26, so "today" is 2026-11-26 and the next
day 2026-11-27. Expected values come from the spec, worked out by hand.
"""

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import select

from feed_the_goose.models import HabitTarget, User
from tests.support import builders

pytestmark = pytest.mark.anyio

TODAY, TOMORROW = "2026-11-26", "2026-11-27"
PUSHUPS = {"name": "Pushups", "unit": "reps", "target": 50, "chunk": 10}


def body(name: str = "Pushups", **overrides):
    return {**PUSHUPS, "name": name, **overrides}


async def create(client, name: str = "Pushups", **overrides):
    response = await client.post("/v1/habits", json=body(name, **overrides))
    assert response.status_code == 201, response.text
    return response.json()


async def chase_changed_at(db, user_id) -> datetime | None:
    await db.rollback()  # a fresh read of the row
    return await db.scalar(select(User.chase_changed_at).where(User.id == user_id))


async def test_a_habit_added_before_the_days_first_log_starts_today(sign_in, db):
    me = await sign_in()

    habit = await create(me.client)

    assert {k: habit[k] for k in (*PUSHUPS, "position", "archived_from")} == {
        **PUSHUPS,
        "position": 0,
        "archived_from": None,
    }
    assert habit["effective_from"] == TODAY
    assert [h["id"] for h in (await me.client.get("/v1/habits")).json()] == [
        habit["id"]
    ]
    # It joins today's chase, so the chase changed.
    assert await chase_changed_at(db, me.user_id) == datetime(
        2026, 11, 26, 15, tzinfo=UTC
    )


async def test_a_habit_added_after_the_days_first_log_starts_tomorrow(sign_in, db):
    me = await sign_in()
    first = await create(me.client)
    await builders.log(db, me.user_id, uuid.UUID(first["id"]))
    await db.commit()
    before = await chase_changed_at(db, me.user_id)

    second = await create(me.client, "Reading", target=20, chunk=5)

    assert second["effective_from"] == TOMORROW
    assert second["position"] == 1
    # Today's set of habits is unchanged, so its chase is too.
    assert await chase_changed_at(db, me.user_id) == before


async def test_an_undone_log_still_counts_as_the_days_first(sign_in, db):
    me = await sign_in()
    first = await create(me.client)
    await builders.log(
        db, me.user_id, uuid.UUID(first["id"]), undone_at=builders.EXAMPLE_START
    )
    await db.commit()

    assert (await create(me.client, "Reading"))["effective_from"] == TOMORROW


async def test_a_habit_added_during_the_night_starts_with_the_next_day(sign_in, clock):
    me = await sign_in()
    # 01:00 on 2026-11-27 in New York: the day of 2026-11-26 has ended, with no log.
    clock.set(datetime(2026, 11, 27, 6, tzinfo=UTC))

    assert (await create(me.client))["effective_from"] == TOMORROW


async def test_a_ninth_habit_is_refused(sign_in):
    me = await sign_in()
    for n in range(8):
        await create(me.client, f"Habit {n}")

    response = await me.client.post("/v1/habits", json=body("Ninth"))

    assert response.status_code == 422
    assert response.json()["type"] == "invalid"
    assert len((await me.client.get("/v1/habits")).json()) == 8


async def test_the_cap_counts_the_habits_of_each_day(sign_in, db):
    me = await sign_in()
    habits = [await create(me.client, f"Habit {n}") for n in range(8)]
    await builders.log(db, me.user_id, uuid.UUID(habits[0]["id"]))
    await db.commit()
    archived = await me.client.delete(f"/v1/habits/{habits[7]['id']}")
    assert archived.json()["archived_from"] == TOMORROW

    # Today keeps eight; tomorrow has seven, so one more fits from tomorrow.
    replacement = await me.client.post("/v1/habits", json=body("Replacement"))
    assert replacement.status_code == 201
    assert replacement.json()["effective_from"] == TOMORROW
    refused = await me.client.post("/v1/habits", json=body("Another"))
    assert refused.status_code == 422


async def test_a_new_target_applies_from_the_next_day(sign_in, db):
    me = await sign_in()
    habit = await create(me.client)
    await builders.log(db, me.user_id, uuid.UUID(habit["id"]), amount=20)
    await db.commit()
    before = await chase_changed_at(db, me.user_id)

    response = await me.client.patch(f"/v1/habits/{habit['id']}", json={"target": 100})

    assert response.status_code == 200
    assert response.json()["target"] == 100
    targets = await db.execute(
        select(HabitTarget.effective_from, HabitTarget.target)
        .where(HabitTarget.habit_id == uuid.UUID(habit["id"]))
        .order_by(HabitTarget.effective_from)
    )
    assert [(str(d), t) for d, t in targets] == [(TODAY, 50), (TOMORROW, 100)]
    assert await chase_changed_at(db, me.user_id) == before

    # A second change the same day replaces the pending target.
    await me.client.patch(f"/v1/habits/{habit['id']}", json={"target": 80})
    await db.rollback()
    targets = await db.scalars(
        select(HabitTarget.target)
        .where(HabitTarget.habit_id == uuid.UUID(habit["id"]))
        .order_by(HabitTarget.effective_from)
    )
    assert list(targets) == [50, 80]


async def test_a_rename_and_a_new_chunk_apply_now(sign_in, db, clock):
    me = await sign_in()
    habit = await create(me.client)
    later = datetime(2026, 11, 26, 16, tzinfo=UTC)
    clock.set(later)

    response = await me.client.patch(
        f"/v1/habits/{habit['id']}",
        # An explicit null is the same as leaving the field out.
        json={"name": "Push-ups", "unit": None, "chunk": 5},
    )

    assert response.status_code == 200
    got = response.json()
    assert (got["name"], got["unit"], got["chunk"], got["target"]) == (
        "Push-ups",
        "reps",
        5,
        50,
    )
    assert got["effective_from"] == TODAY
    assert await chase_changed_at(db, me.user_id) == later


async def test_reordering_moves_one_habit_and_keeps_the_others_in_order(sign_in):
    me = await sign_in()
    a, b, c = [await create(me.client, n) for n in ("A", "B", "C")]

    moved = await me.client.patch(f"/v1/habits/{c['id']}", json={"position": 0})

    assert moved.json()["position"] == 0
    listed = (await me.client.get("/v1/habits")).json()
    assert [(h["name"], h["position"]) for h in listed] == [
        ("C", 0),
        ("A", 1),
        ("B", 2),
    ]
    # A position past the end puts the habit last.
    await me.client.patch(f"/v1/habits/{c['id']}", json={"position": 99})
    listed = (await me.client.get("/v1/habits")).json()
    assert [(h["name"], h["position"]) for h in listed] == [
        ("A", 0),
        ("B", 1),
        ("C", 2),
    ]
    assert {a["id"], b["id"]} <= {h["id"] for h in listed}


async def test_an_archived_habit_stays_today_and_is_gone_tomorrow(sign_in, clock):
    me = await sign_in()
    habit = await create(me.client)

    archived = await me.client.delete(f"/v1/habits/{habit['id']}")

    assert archived.status_code == 200
    assert archived.json()["archived_from"] == TOMORROW
    again = await me.client.delete(f"/v1/habits/{habit['id']}")
    assert again.json()["archived_from"] == TOMORROW
    assert [h["id"] for h in (await me.client.get("/v1/habits")).json()] == [
        habit["id"]
    ]

    clock.set(datetime(2026, 11, 27, 12, tzinfo=UTC))  # 07:00 on 2026-11-27

    assert (await me.client.get("/v1/habits")).json() == []
    patched = await me.client.patch(f"/v1/habits/{habit['id']}", json={"name": "X"})
    assert patched.status_code == 404
    assert patched.json()["type"] == "not_found"


async def test_an_upcoming_habit_archived_before_it_starts_is_gone(sign_in, db):
    me = await sign_in()
    first = await create(me.client)
    await builders.log(db, me.user_id, uuid.UUID(first["id"]))
    await db.commit()
    upcoming = await create(me.client, "Reading")

    archived = await me.client.delete(f"/v1/habits/{upcoming['id']}")
    again = await me.client.delete(f"/v1/habits/{upcoming['id']}")

    assert archived.json()["archived_from"] == TOMORROW
    assert again.status_code == 200
    assert [h["id"] for h in (await me.client.get("/v1/habits")).json()] == [
        first["id"]
    ]


async def test_another_users_habit_is_not_found(sign_in):
    mine, theirs = await sign_in(), await sign_in()
    habit = await create(theirs.client)
    path = f"/v1/habits/{habit['id']}"

    assert (await mine.client.patch(path, json={"name": "Mine"})).status_code == 404
    assert (await mine.client.delete(path)).status_code == 404
    assert (await mine.client.get("/v1/habits")).json() == []
    assert (await theirs.client.get(path.rsplit("/", 1)[0])).json()[0]["name"] == (
        "Pushups"
    )


@pytest.mark.parametrize(
    "fields",
    [{"target": 0}, {"chunk": 0}, {"name": ""}, {"colour": "red"}],
    ids=["zero target", "zero chunk", "empty name", "unknown field"],
)
async def test_invalid_habits_are_refused(sign_in, fields):
    me = await sign_in()

    response = await me.client.post("/v1/habits", json=body(**fields))

    assert response.status_code == 422
    assert response.json()["type"] == "invalid"
