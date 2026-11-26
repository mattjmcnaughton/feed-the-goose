"""Logging, undoing and listing logs (TDD §5.5, constitution §3).

The client sets a log's ID and `logged_at` once. A repeated ID is the same log, and
an undone log stays undone. Every write locks the user's row, so the writes that
make up one log or undo succeed or fail together.
"""

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from enum import StrEnum
from fractions import Fraction
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.models import Log
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.repositories.habits import HabitRepository
from feed_the_goose.repositories.logs import LogRepository
from feed_the_goose.services.chase import ChaseService, ChaseView
from feed_the_goose.services.days import DaysService, Ensured, RefusedError


class NotFoundError(RefusedError):
    """No such habit or log for this user."""


class DaySettledError(RefusedError):
    """The log's day has settled."""


class InvalidLogError(RefusedError):
    """The log cannot be accepted. `field` names the request field at fault."""

    def __init__(self, field: str) -> None:
        super().__init__(field)
        self.field = field


class EventKind(StrEnum):
    gain = "gain"
    complete = "complete"
    caught = "caught"
    undone = "undone"


@dataclass(frozen=True)
class Event:
    kind: EventKind
    habit_id: UUID
    steps: Fraction


@dataclass(frozen=True)
class LoggedResult:
    """A log, what it did, and the current chase. `created` is False when the ID
    already existed."""

    log: Log
    steps: Fraction
    event: Event
    chase: ChaseView
    created: bool


@dataclass(frozen=True)
class NewLog:
    id: UUID
    habit_id: UUID
    amount: int | None
    logged_at: datetime
    source: str


class LogService:
    def __init__(
        self,
        *,
        settings: Settings,
        clock: Clock,
        days: DaysService,
        chase: ChaseService,
    ) -> None:
        self._settings = settings
        self._clock = clock
        self._days = days
        self._chase = chase

    async def create(self, user_id: UUID, new: NewLog) -> LoggedResult:
        """Store a log, or return the stored one when its ID exists.

        A log counts at its `logged_at`, in the day that instant belongs to. One
        stamped ahead of the server's clock, within the allowed skew, is handled
        as of its `logged_at`, so its day exists and the chase returned counts it.
        """
        now = self._clock.now()
        skew = timedelta(seconds=self._settings.log_clock_skew_seconds)
        at = min(max(now, new.logged_at), now + skew)
        async with self._days.transaction(user_id, at) as (db, ensured):
            logs = LogRepository(db)
            existing = await logs.get(new.id)
            if existing is None:
                row = await self._accept(db, ensured, new, now)
                if await logs.insert(row):
                    ensured.user.chase_changed_at = now
                    return await self._result(db, ensured, row, at, created=True)
                # Another user stored this ID while we checked.
                existing = await logs.get(new.id)
                assert existing is not None
            if existing.user_id != user_id:
                raise InvalidLogError("id")
            return await self._result(db, ensured, existing, at, created=False)

    async def undo(self, user_id: UUID, log_id: UUID) -> LoggedResult:
        """Undo a log of a day that has not settled. Undoing twice is the same."""
        now = self._clock.now()
        async with self._days.transaction(user_id, now) as (db, ensured):
            log = await LogRepository(db).get(log_id)
            if log is None or log.user_id != user_id:
                raise NotFoundError
            day = await DayRepository(db).get(user_id, log.date)
            assert day is not None
            if day.settled_at is not None:
                raise DaySettledError
            if log.undone_at is None:
                log.undone_at = now
                ensured.user.chase_changed_at = now
                await db.flush()
            return await self._result(db, ensured, log, now, created=False)

    async def for_day(self, user_id: UUID, day: date) -> list[tuple[Log, Fraction]]:
        """A day's logs, newest first, undone ones included, with what each counts
        for now."""
        now = self._clock.now()
        async with self._days.transaction(user_id, now) as (db, ensured):
            row = await DayRepository(db).get(user_id, day)
            if row is None:
                return []
            record = await self._days.record(db, ensured.calendar, row)
            steps = record.steps_by_log()
            return [
                (log, steps[log.id])
                for log in sorted(
                    record.logs, key=lambda log: (log.logged_at, log.id), reverse=True
                )
            ]

    async def _accept(
        self, db: AsyncSession, ensured: Ensured, new: NewLog, now: datetime
    ) -> Log:
        """The row for a new log, once the log is checked against its day."""
        habit = await HabitRepository(db).get(ensured.user.id, new.habit_id)
        if habit is None:
            raise NotFoundError
        skew = timedelta(seconds=self._settings.log_clock_skew_seconds)
        if new.logged_at > now + skew:
            raise InvalidLogError("logged_at")
        day = ensured.calendar.date_of(new.logged_at)
        row = await DayRepository(db).get(ensured.user.id, day)
        if row is not None and row.settled_at is not None:
            raise DaySettledError
        if row is None:
            # Before the first day, or on a date with no habit.
            raise InvalidLogError("logged_at")
        if all(h.habit.id != habit.id for h in ensured.calendar.habits_on(day)):
            raise InvalidLogError("habit_id")
        return Log(
            id=new.id,
            user_id=ensured.user.id,
            habit_id=habit.id,
            amount=new.amount if new.amount is not None else habit.chunk,
            logged_at=new.logged_at,
            received_at=now,
            source=new.source,
            date=day,
            undone_at=None,
        )

    async def _result(
        self,
        db: AsyncSession,
        ensured: Ensured,
        log: Log,
        now: datetime,
        *,
        created: bool,
    ) -> LoggedResult:
        row = await DayRepository(db).get(log.user_id, log.date)
        assert row is not None
        record = await self._days.record(db, ensured.calendar, row)
        outcome = record.outcome(log)
        if log.undone_at is not None:
            event = Event(EventKind.undone, log.habit_id, outcome.steps)
            steps = Fraction(0)
        else:
            event = Event(EventKind(outcome.kind.value), log.habit_id, outcome.steps)
            steps = outcome.steps
        # The current chase. A replay with no current day, after the habits were
        # archived, gets its own day's, so that a retry still succeeds.
        if ensured.current is None:
            chase = self._chase.view(ensured.user.pursuer, record, now)
        else:
            chase = await self._chase.current(db, ensured, now)
        return LoggedResult(
            log=log, steps=steps, event=event, chase=chase, created=created
        )
