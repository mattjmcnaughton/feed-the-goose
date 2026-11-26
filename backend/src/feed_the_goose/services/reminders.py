"""Reminder preferences, and the worker's two jobs: planning and sending
(TDD §5.9, PRD S14).

The worker learns that a chase changed through the database: every write that
changes one raises `users.chase_version` under the user's lock, and planning
stores the version it read under that lock in `reminders_planned_version` and the
day start it covered in `reminders_planned_at`. A counter, unlike a time read
before the lock, cannot fall behind the last plan.
"""

from dataclasses import dataclass
from datetime import datetime, time, timedelta
from typing import TYPE_CHECKING

import structlog
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.models import PushJob, User
from feed_the_goose.push import planner
from feed_the_goose.push.config import PushSettings
from feed_the_goose.push.sender import Outcome, PushSender
from feed_the_goose.repositories.installations import InstallationRepository
from feed_the_goose.repositories.push_jobs import PushJobRepository
from feed_the_goose.services.accounts import lock_user
from feed_the_goose.services.auth import Principal
from feed_the_goose.services.days import DaysService, Ensured

if TYPE_CHECKING:
    from uuid import UUID

log = structlog.get_logger()

# Reminders tried in one sending pass.
CLAIM_LIMIT = 100


@dataclass(frozen=True)
class ReminderPreferences:
    enabled: bool
    when_lead_below: int
    # Local start and end, or None.
    quiet_hours: tuple[time, time] | None


class ReminderService:
    def __init__(
        self,
        *,
        settings: Settings,
        push: PushSettings,
        clock: Clock,
        sessions: async_sessionmaker[AsyncSession],
        days: DaysService,
        sender: PushSender,
    ) -> None:
        self._settings = settings
        self._push = push
        self._clock = clock
        self._sessions = sessions
        self._days = days
        self._sender = sender

    async def get(self, principal: Principal) -> ReminderPreferences:
        async with self._sessions.begin() as db:
            return _preferences(await lock_user(db, principal))

    async def update(
        self, principal: Principal, preferences: ReminderPreferences
    ) -> ReminderPreferences:
        """Save the preferences. The worker plans again on its next pass; turning
        reminders off drops the ones not yet sent."""
        async with self._sessions.begin() as db:
            user = await lock_user(db, principal)
            user.reminders_enabled = preferences.enabled
            user.reminder_lead_below = preferences.when_lead_below
            user.quiet_hours_start, user.quiet_hours_end = preferences.quiet_hours or (
                None,
                None,
            )
            user.reminders_planned_at = None
            if not preferences.enabled:
                await PushJobRepository(db).delete_unsent(user.id)
            return _preferences(user)

    async def run_pass(self) -> tuple[int, int]:
        """One worker pass: plan, then send. Returns the users planned and the
        reminders sent."""
        return await self.plan(), await self.send_due()

    async def plan(self) -> int:
        """Plan the current day's reminders of each user whose chase changed or
        whose day is new since they were last planned. A user who cannot be
        planned is logged and skipped, so the others still are."""
        now = self._clock.now()
        async with self._sessions() as db:
            user_ids = await PushJobRepository(db).users_with_reminders()
        planned = 0
        for user_id in user_ids:
            try:
                async with self._days.transaction(user_id, now) as (db, ensured):
                    planned += await self._plan_user(db, ensured, now)
            except Exception:
                log.exception("reminders_not_planned", user_id=str(user_id))
        return planned

    async def _plan_user(
        self, db: AsyncSession, ensured: Ensured, now: datetime
    ) -> bool:
        user, current = ensured.user, ensured.current
        last = user.reminders_planned_at
        if not user.reminders_enabled or not (
            last is None
            or user.chase_version != user.reminders_planned_version
            or (current is not None and current.starts_at > last)
        ):
            return False
        if current is not None:
            record = await self._days.record(db, ensured.calendar, current)
            preferences = planner.Preferences(
                when_lead_below=user.reminder_lead_below,
                quiet_hours=_preferences(user).quiet_hours,
                time_zone=ensured.calendar.settings_for(current.date).time_zone,
            )
            remind_before = timedelta(seconds=self._settings.reminder_before_seconds)
            reminders = planner.plan(
                record.window,
                record.chase_at(now),
                preferences,
                remind_before=remind_before,
            )
            await PushJobRepository(db).replace_unsent(
                user.id,
                current.date,
                [
                    PushJob(
                        kind=r.kind.value,
                        due_at=r.due_at,
                        payload=planner.payload(
                            r.kind,
                            current.date,
                            when_lead_below=user.reminder_lead_below,
                            remind_before=remind_before,
                        ),
                    )
                    for r in reminders
                ],
            )
            log.info(
                "reminders_planned",
                user_id=str(user.id),
                date=current.date.isoformat(),
                due={r.kind.value: r.due_at.isoformat() for r in reminders},
            )
        user.reminders_planned_version = user.chase_version
        user.reminders_planned_at = current.starts_at if current else now
        return True

    async def send_due(self) -> int:
        """Send each due reminder to each of its user's installations, once.

        Each reminder is claimed, sent and marked in its own transaction, so a
        failure later in the pass cannot unmark one already sent, and no lock is
        held for longer than one reminder's sends.
        """
        now = self._clock.now()
        tried: list[UUID] = []
        sent = 0
        while len(tried) < CLAIM_LIMIT:
            async with self._sessions.begin() as db:
                jobs = PushJobRepository(db)
                [job] = await jobs.claim_due(
                    now,
                    since=now - timedelta(seconds=self._push.push_stale_after_seconds),
                    max_attempts=self._push.push_max_attempts,
                    exclude=tried,
                    limit=1,
                ) or [None]
                if job is None:
                    break
                tried.append(job.id)
                sent += await self._send(db, job, now)
        return sent

    async def _send(self, db: AsyncSession, job: PushJob, now: datetime) -> bool:
        installations = InstallationRepository(db)
        outcomes = []
        for installation in await installations.for_user(job.user_id):
            token = installation.apns_token
            if token is None:
                continue
            outcome = await self._sender.send(installation, job.payload)
            if outcome is Outcome.UNREGISTERED:
                await installations.clear_apns_token(installation.id, token)
            outcomes.append(outcome)
        # Tried again on a later pass only when every installation failed for a
        # reason that may pass, so that no installation gets it twice.
        if outcomes and all(o is Outcome.FAILED for o in outcomes):
            await PushJobRepository(db).mark_failed(job.id)
            return False
        await PushJobRepository(db).mark_sent(job.id, now)
        log.info(
            "reminder_sent",
            user_id=str(job.user_id),
            kind=job.kind,
            installations=outcomes.count(Outcome.SENT),
        )
        return True


def _preferences(user: User) -> ReminderPreferences:
    quiet = None
    if user.quiet_hours_start is not None and user.quiet_hours_end is not None:
        quiet = (user.quiet_hours_start, user.quiet_hours_end)
    return ReminderPreferences(
        enabled=user.reminders_enabled,
        when_lead_below=user.reminder_lead_below,
        quiet_hours=quiet,
    )
