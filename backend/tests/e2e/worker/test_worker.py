"""The reminder worker with the recording sender, against the served app
(TDD §5.9, PRD S14).

The user's day runs from 10:00 to 00:00 at 100/18 steps an hour from a lead of
100, with reminders below 60 and an hour before the day's end. Times are local to
New York and worked out by hand:

- the lead falls below 60 after 40 / (100/18) = 7.2 hours: 17:12;
- after a log of 10 of the 50 Pushups (20 steps), after 10.8 hours: 20:48;
- the day ends at 00:00, so its reminder is due at 23:00;
- the lead stays above 0 until the day's end, so there is no catch reminder.
"""

import asyncio
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import anyio
import pytest
from sqlalchemy import delete, select

from feed_the_goose import worker
from feed_the_goose.models import PushJob, User
from feed_the_goose.push.recording import RecordingSender
from feed_the_goose.services.days import DaysService
from feed_the_goose.services.logs import LogService, NewLog
from feed_the_goose.services.reminders import ReminderService
from tests.conftest import NOW

pytestmark = pytest.mark.anyio

LEAD_LOW, DAY_END = "lead_low", "before_day_end"


def local(hour: int, minute: int = 0) -> datetime:
    return datetime(
        2026, 11, 26, hour, minute, tzinfo=ZoneInfo("America/New_York")
    ).astimezone(UTC)


async def jobs(wired, user_id) -> dict[str, PushJob]:
    async with wired.sessions() as db:
        rows = await db.scalars(select(PushJob).where(PushJob.user_id == user_id))
        return {job.kind: job for job in rows}


def due(found: dict[str, PushJob]) -> dict[str, datetime]:
    return {kind: job.due_at for kind, job in found.items()}


async def log(account, amount: int, at: datetime) -> None:
    response = await account.rest.post(
        "/v1/logs",
        json={
            "id": str(uuid.uuid4()),
            "habit_id": account.habit_id,
            "amount": amount,
            "logged_at": at.isoformat(),
            "source": "app",
        },
    )
    assert response.status_code == 201, response.text


async def wait_for(check, timeout: float = 10):
    with anyio.fail_after(timeout):
        while not (found := await check()):
            await anyio.sleep(0.05)
        return found


async def test_a_log_through_the_api_moves_a_reminder_with_the_worker_running(
    wired, account, clock
):
    wired.push.worker_interval_seconds = 0.05
    stop = asyncio.Event()
    running = asyncio.create_task(worker.run(wired, stop))
    try:
        before = await wait_for(lambda: jobs(wired, account.user_id))
        assert due(before) == {LEAD_LOW: local(17, 12), DAY_END: local(23)}

        clock.set(NOW + timedelta(minutes=1))
        await log(account, 10, clock.now())

        async def moved():
            found = await jobs(wired, account.user_id)
            return found if found[LEAD_LOW].due_at != local(17, 12) else None

        after = await wait_for(moved)
        assert due(after) == {LEAD_LOW: local(20, 48), DAY_END: local(23)}
    finally:
        stop.set()
        await running


async def test_a_reminder_is_sent_once_across_two_passes(wired, account, clock):
    reminders = wired.reminders
    assert await reminders.run_pass() == (1, 0)

    clock.set(local(17, 12))
    assert await reminders.run_pass() == (0, 1)
    assert await reminders.run_pass() == (0, 0)

    found = await jobs(wired, account.user_id)
    assert found[LEAD_LOW].sent_at == local(17, 12)
    assert found[DAY_END].sent_at is None

    # A log replans the day, but the lead going low again is not sent again.
    clock.set(local(17, 13))
    await log(account, 10, clock.now())
    assert await reminders.run_pass() == (1, 0)
    clock.set(local(22, 0))
    assert await reminders.run_pass() == (0, 0)

    pushes = await account.rest.get("/dev/pushes", params={"email": account.email})
    assert pushes.status_code == 200
    assert [(p["installation_id"], p["payload"]["kind"]) for p in pushes.json()] == [
        (account.installation_id, LEAD_LOW)
    ]
    assert pushes.json()[0]["payload"]["aps"]["alert"] == {
        "title": "Your lead is low",
        "body": "Your lead is below 60 steps. Log a habit to get ahead.",
    }


async def test_a_change_stamped_before_a_pass_but_saved_after_it_is_planned(
    wired, account, clock
):
    # The web process read its clock at 10:01, then waited for the user's lock
    # while the worker planned at 10:05.
    clock.set(NOW + timedelta(minutes=5))
    assert await wired.reminders.run_pass() == (1, 0)
    clock.set(NOW + timedelta(minutes=1))
    await log(account, 10, clock.now())

    assert await wired.reminders.run_pass() == (1, 0)
    assert due(await jobs(wired, account.user_id))[LEAD_LOW] == local(20, 48)


class HeldDays(DaysService):
    """Holds each transaction until `go` is set, as a request delayed between
    reading its clock and taking the user's lock would be."""

    def __init__(self, wired) -> None:
        super().__init__(settings=wired.settings, sessions=wired.sessions)
        self.waiting, self.go = asyncio.Event(), asyncio.Event()

    @asynccontextmanager
    async def transaction(self, user_id, now):
        self.waiting.set()
        await self.go.wait()
        async with super().transaction(user_id, now) as opened:
            yield opened


async def test_two_overlapping_logs_are_both_planned(wired, account, clock):
    # Log A of 5 Pushups reads its clock at 10:01 and is held before the lock. Log
    # B of 10 reads 10:05, saves, and the worker plans it at 10:05. Then A saves.
    held = HeldDays(wired)
    slow = LogService(
        settings=wired.settings, clock=clock, days=held, chase=wired.chase
    )
    clock.set(NOW + timedelta(minutes=1))
    a = asyncio.create_task(
        slow.create(
            account.user_id,
            NewLog(
                id=uuid.uuid4(),
                habit_id=uuid.UUID(account.habit_id),
                amount=5,
                logged_at=clock.now(),
                source="app",
            ),
        )
    )
    await held.waiting.wait()
    clock.set(NOW + timedelta(minutes=5))
    await log(account, 10, clock.now())
    assert await wired.reminders.run_pass() == (1, 0)
    held.go.set()
    await a

    assert await wired.reminders.run_pass() == (1, 0)
    # 10 + 20 steps: the lead falls below 60 after 70 / (100/18) = 12.6 hours.
    assert due(await jobs(wired, account.user_id)) == {
        LEAD_LOW: local(22, 36),
        DAY_END: local(23),
    }


async def test_preferences_round_trip_and_turning_them_off_drops_unsent_reminders(
    wired, account
):
    quiet = {"start": "22:00", "end": "07:00"}
    preferences = {"enabled": True, "when_lead_below": 60, "quiet_hours": quiet}
    saved = await account.rest.put("/v1/me/reminders", json=preferences)
    assert saved.json() == preferences
    assert (await account.rest.get("/v1/me/reminders")).json() == preferences

    await wired.reminders.run_pass()
    # 23:00 is in quiet hours.
    assert due(await jobs(wired, account.user_id)) == {LEAD_LOW: local(17, 12)}

    off = {**preferences, "enabled": False}
    assert (await account.rest.put("/v1/me/reminders", json=off)).json() == off
    assert await jobs(wired, account.user_id) == {}
    assert await wired.reminders.run_pass() == (0, 0)


async def test_preferences_without_quiet_hours_mean_none(wired, account, clock):
    # The contract marks `quiet_hours` optional, and the app's generated client leaves
    # a nil one out of the body instead of sending null.
    saved = await account.rest.put(
        "/v1/me/reminders", json={"enabled": True, "when_lead_below": 40}
    )
    assert saved.status_code == 200, saved.text
    expected = {"enabled": True, "when_lead_below": 40, "quiet_hours": None}
    assert saved.json() == expected
    assert (await account.rest.get("/v1/me/reminders")).json() == expected


async def test_a_deleted_installation_gets_nothing(wired, account, clock):
    deleted = await account.rest.delete(f"/v1/me/devices/{account.installation_id}")
    assert deleted.status_code == 204

    await wired.reminders.run_pass()
    clock.set(local(17, 12))
    await wired.reminders.run_pass()

    pushes = await account.rest.get("/dev/pushes", params={"email": account.email})
    assert pushes.json() == []


class CrashesOnSecondSend:
    """Records the first push, then fails the way a lost connection would."""

    def __init__(self, wired) -> None:
        self.recording = RecordingSender(clock=wired.clock, sessions=wired.sessions)
        self.calls = 0

    async def send(self, installation, payload):
        self.calls += 1
        if self.calls > 1:
            raise ConnectionError("lost")
        return await self.recording.send(installation, payload)


async def test_a_crash_mid_pass_does_not_send_an_earlier_reminder_again(
    wired, account, clock
):
    push = wired.push.model_copy(update={"push_stale_after_seconds": 86400})
    crashing = ReminderService(
        settings=wired.settings,
        push=push,
        clock=clock,
        sessions=wired.sessions,
        days=DaysService(settings=wired.settings, sessions=wired.sessions),
        sender=CrashesOnSecondSend(wired),
    )
    await crashing.plan()
    # Both the 17:12 and the 23:00 reminders are due.
    clock.set(local(23, 0))
    with pytest.raises(ConnectionError):
        await crashing.send_due()

    found = await jobs(wired, account.user_id)
    assert found[LEAD_LOW].sent_at == local(23, 0)
    assert found[DAY_END].sent_at is None

    healthy = ReminderService(
        settings=wired.settings,
        push=push,
        clock=clock,
        sessions=wired.sessions,
        days=DaysService(settings=wired.settings, sessions=wired.sessions),
        sender=RecordingSender(clock=clock, sessions=wired.sessions),
    )
    assert await healthy.send_due() == 1
    pushes = await account.rest.get("/dev/pushes", params={"email": account.email})
    assert sorted(p["payload"]["kind"] for p in pushes.json()) == [DAY_END, LEAD_LOW]


async def test_a_user_who_cannot_be_planned_does_not_stop_the_others(
    wired, account, clock
):
    # Enabled, but with no day settings, so their days cannot be worked out. They
    # are the oldest user, so they come first.
    async with wired.sessions.begin() as db:
        broken = User(
            identity_subject=f"dev|broken-{uuid.uuid4()}",
            email="broken@example.com",
            display_name="broken",
            pursuer="goose",
            reminders_enabled=True,
            reminder_lead_below=30,
            created_at=datetime(2000, 1, 1, tzinfo=UTC),
        )
        db.add(broken)
    try:
        assert await wired.reminders.run_pass() == (1, 0)
        clock.set(local(17, 12))
        assert await wired.reminders.run_pass() == (0, 1)
    finally:
        async with wired.sessions.begin() as db:
            await db.execute(delete(User).where(User.id == broken.id))
