"""Habits and their targets (owned by T05 after T04)."""

from datetime import date
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Habit, HabitTarget


class HabitRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def add(self, habit: Habit, target: int) -> Habit:
        """Add a habit with its first target, effective from the habit's first day."""
        self._session.add(habit)
        await self._session.flush()
        await self.add_target(habit.id, habit.effective_from, target)
        return habit

    async def add_target(
        self, habit_id: UUID, effective_from: date, target: int
    ) -> HabitTarget:
        row = HabitTarget(
            habit_id=habit_id, effective_from=effective_from, target=target
        )
        self._session.add(row)
        await self._session.flush()
        return row

    async def set_target(
        self, habit_id: UUID, effective_from: date, target: int
    ) -> None:
        """Set the target from `effective_from`, replacing one already set for it."""
        await self._session.execute(
            insert(HabitTarget)
            .values(habit_id=habit_id, effective_from=effective_from, target=target)
            .on_conflict_do_update(
                index_elements=["habit_id", "effective_from"],
                set_={"target": target},
            )
        )

    async def get(self, user_id: UUID, habit_id: UUID) -> Habit | None:
        """The user's habit with that ID; another user's habit is not found."""
        return await self._session.scalar(
            select(Habit).where(Habit.id == habit_id, Habit.user_id == user_id)
        )

    async def for_user(self, user_id: UUID) -> list[Habit]:
        """Every habit of the user's, archived ones included, in position order."""
        rows = await self._session.scalars(
            select(Habit)
            .where(Habit.user_id == user_id)
            .order_by(Habit.position, Habit.created_at)
        )
        return list(rows)

    async def targets(self, habit_id: UUID) -> list[HabitTarget]:
        """The habit's targets, oldest `effective_from` first."""
        rows = await self._session.scalars(
            select(HabitTarget)
            .where(HabitTarget.habit_id == habit_id)
            .order_by(HabitTarget.effective_from)
        )
        return list(rows)

    async def latest_targets(self, habit_ids: list[UUID]) -> dict[UUID, int]:
        """Each habit's target with the latest `effective_from`."""
        rows = await self._session.execute(
            select(HabitTarget.habit_id, HabitTarget.target)
            .where(HabitTarget.habit_id.in_(habit_ids))
            .order_by(HabitTarget.effective_from)
        )
        return {habit_id: target for habit_id, target in rows}
