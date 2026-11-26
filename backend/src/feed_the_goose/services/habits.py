"""Habits (API spec "Habits", constitution §4).

A habit belongs to a date when `effective_from <= date < archived_from`. The set of
habits and their targets change from the next day, so the shares of the day under
way never change. Renames, a new chunk and reordering apply now. Every write locks
the user's row, as the chase does, so it cannot race a log or another edit.
"""

from dataclasses import dataclass
from datetime import date
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.models import Habit
from feed_the_goose.repositories.habits import HabitRepository
from feed_the_goose.repositories.logs import LogRepository
from feed_the_goose.services.accounts import CurrentDay, current_day, lock_user
from feed_the_goose.services.auth import Principal


class HabitNotFoundError(Exception):
    """No active or upcoming habit of the user's has that ID."""


class TooManyHabitsError(Exception):
    """The habit would make a day's habits more than the cap."""


@dataclass(frozen=True)
class HabitView:
    """A habit and its latest target: the one that applies from the next day, or
    today's when it has not changed."""

    habit: Habit
    target: int


@dataclass(frozen=True)
class HabitChanges:
    """Fields to change; None leaves a field as it is."""

    name: str | None = None
    unit: str | None = None
    target: int | None = None
    chunk: int | None = None
    position: int | None = None


def belongs(habit: Habit, day: date) -> bool:
    return habit.effective_from <= day and (
        habit.archived_from is None or day < habit.archived_from
    )


def _listed(habit: Habit, today: date) -> bool:
    """Active today or upcoming: it belongs to today or to some later date."""
    return habit.archived_from is None or habit.archived_from > max(
        today, habit.effective_from
    )


class HabitService:
    def __init__(
        self,
        *,
        settings: Settings,
        clock: Clock,
        sessions: async_sessionmaker[AsyncSession],
    ) -> None:
        self._settings = settings
        self._clock = clock
        self._sessions = sessions

    async def listed(self, principal: Principal) -> list[HabitView]:
        """Active and upcoming habits, in position order."""
        async with self._sessions.begin() as db:
            day = await self._day(db, principal.user_id)
            habits = await HabitRepository(db).for_user(principal.user_id)
            return await self._views(db, [h for h in habits if _listed(h, day.date)])

    async def create(
        self, principal: Principal, *, name: str, unit: str, target: int, chunk: int
    ) -> HabitView:
        """Add a habit from the current day when it is under way and has no log
        yet, and otherwise from the next day."""
        now = self._clock.now()
        async with self._sessions.begin() as db:
            user = await lock_user(db, principal)
            day = await self._day(db, user.id)
            starts_today = now < day.ends_at and not await LogRepository(
                db
            ).exists_for_day(user.id, day.date)
            effective_from = day.date if starts_today else day.next_date
            habits = await HabitRepository(db).for_user(user.id)
            for on in {effective_from, day.next_date}:
                if sum(belongs(h, on) for h in habits) >= self._settings.max_habits:
                    raise TooManyHabitsError
            listed = [h for h in habits if _listed(h, day.date)]
            habit = await HabitRepository(db).add(
                Habit(
                    user_id=user.id,
                    name=name,
                    unit=unit,
                    chunk=chunk,
                    position=max((h.position for h in listed), default=-1) + 1,
                    effective_from=effective_from,
                    archived_from=None,
                    created_at=now,
                ),
                target,
            )
            if starts_today:
                user.chase_changed_at = now
            return HabitView(habit, target)

    async def update(
        self, principal: Principal, habit_id: UUID, changes: HabitChanges
    ) -> HabitView:
        """Rename, re-chunk and reorder now; change the target from the next day."""
        now = self._clock.now()
        async with self._sessions.begin() as db:
            user = await lock_user(db, principal)
            day = await self._day(db, user.id)
            repository = HabitRepository(db)
            habits = [
                h for h in await repository.for_user(user.id) if _listed(h, day.date)
            ]
            habit = next((h for h in habits if h.id == habit_id), None)
            if habit is None:
                raise HabitNotFoundError
            changed_now = False
            for field in ("name", "unit", "chunk"):
                value = getattr(changes, field)
                if value is not None and value != getattr(habit, field):
                    setattr(habit, field, value)
                    changed_now = True
            if changes.position is not None:
                order = [h for h in habits if h is not habit]
                order.insert(min(changes.position, len(order)), habit)
                changed_now |= order != habits
                for position, h in enumerate(order):
                    h.position = position
            target = (await repository.latest_targets([habit.id]))[habit.id]
            if changes.target is not None and changes.target != target:
                await repository.set_target(habit.id, day.next_date, changes.target)
                target = changes.target
            if changed_now and belongs(habit, day.date):
                user.chase_changed_at = now
            return HabitView(habit, target)

    async def archive(self, principal: Principal, habit_id: UUID) -> HabitView:
        """Archive from the next day. Archiving again changes nothing."""
        async with self._sessions.begin() as db:
            user = await lock_user(db, principal)
            day = await self._day(db, user.id)
            habit = await HabitRepository(db).get(user.id, habit_id)
            if habit is None or (
                habit.archived_from is not None and habit.archived_from <= day.date
            ):
                raise HabitNotFoundError
            if habit.archived_from is None:
                habit.archived_from = day.next_date
            return (await self._views(db, [habit]))[0]

    async def _day(self, db: AsyncSession, user_id: UUID) -> CurrentDay:
        return await current_day(
            db, user_id, self._clock.now(), steps_per_day=self._settings.steps_per_day
        )

    async def _views(self, db: AsyncSession, habits: list[Habit]) -> list[HabitView]:
        targets = await HabitRepository(db).latest_targets([h.id for h in habits])
        return [HabitView(h, targets[h.id]) for h in habits]
