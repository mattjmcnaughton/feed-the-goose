"""Habits (API spec "Habits").

A stub from T02: each route answers 501 `not_implemented` until T05 lands.
"""

from uuid import UUID

from fastapi import APIRouter

from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.habits import Habit, HabitCreate, HabitUpdate
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/habits", tags=["habits"])


@router.get("", operation_id="listHabits", responses=problems(P.unauthenticated))
async def list_habits() -> list[Habit]:
    """Active and upcoming habits."""
    raise not_implemented()


@router.post(
    "",
    status_code=201,
    operation_id="createHabit",
    responses=problems(P.unauthenticated, P.invalid),
)
async def create_habit(body: HabitCreate) -> Habit:
    raise not_implemented()


@router.patch(
    "/{habit_id}",
    operation_id="updateHabit",
    responses=problems(P.unauthenticated, P.not_found, P.invalid),
)
async def update_habit(habit_id: UUID, body: HabitUpdate) -> Habit:
    raise not_implemented()


@router.delete(
    "/{habit_id}",
    operation_id="archiveHabit",
    responses=problems(P.unauthenticated, P.not_found, P.invalid),
)
async def archive_habit(habit_id: UUID) -> Habit:
    """Archive a habit from the next day."""
    raise not_implemented()
