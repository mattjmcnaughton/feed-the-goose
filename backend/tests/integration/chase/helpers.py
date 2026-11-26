"""Helpers for the chase tests: the TDD §5.3 example day's three habits."""

from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Day, Habit
from tests.support import builders


async def three_habits(db: AsyncSession, user_id: UUID, **kwargs) -> list[Habit]:
    """Pushups 50 by 10, Workout 30 by 10, Reading 20 by 5, committed."""
    habits = [
        await builders.habit(
            db,
            user_id,
            name=name,
            unit=unit,
            target=target,
            chunk=chunk,
            position=i,
            **kwargs,
        )
        for i, (name, unit, target, chunk) in enumerate(
            [
                ("Pushups", "reps", 50, 10),
                ("Workout", "minutes", 30, 10),
                ("Reading", "pages", 20, 5),
            ]
        )
    ]
    await db.commit()
    return habits


def log_body(
    habit_id: UUID, logged_at: str, amount: int | None = 10, log_id: UUID | None = None
) -> dict:
    body = {
        "id": str(log_id or uuid4()),
        "habit_id": str(habit_id),
        "logged_at": logged_at,
        "source": "app",
    }
    if amount is not None:
        body["amount"] = amount
    return body


async def day_rows(db: AsyncSession, user_id: UUID) -> list[dict]:
    """The user's day rows as stored now, oldest first."""
    result = await db.execute(
        select(Day.__table__).where(Day.user_id == user_id).order_by(Day.date)
    )
    return [dict(row) for row in result.mappings()]
