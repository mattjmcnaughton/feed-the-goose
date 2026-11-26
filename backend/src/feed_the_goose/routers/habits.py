"""Habits (API spec "Habits")."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from feed_the_goose.controllers import habits as controller
from feed_the_goose.deps import ApiPrincipal, wiring
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.habits import Habit, HabitCreate, HabitUpdate
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

router = APIRouter(prefix="/v1/habits", tags=["habits"])

WiringDep = Annotated[Wiring, Depends(wiring)]


@router.get("", operation_id="listHabits", responses=problems(P.unauthenticated))
async def list_habits(principal: ApiPrincipal, w: WiringDep) -> list[Habit]:
    """Active and upcoming habits."""
    return await controller.list_habits(w.habits, principal)


@router.post(
    "",
    status_code=201,
    operation_id="createHabit",
    responses=problems(P.unauthenticated, P.invalid),
)
async def create_habit(
    body: HabitCreate, principal: ApiPrincipal, w: WiringDep
) -> Habit:
    return await controller.create_habit(
        w.habits, principal, body, w.settings.max_habits
    )


@router.patch(
    "/{habit_id}",
    operation_id="updateHabit",
    responses=problems(P.unauthenticated, P.not_found, P.invalid),
)
async def update_habit(
    habit_id: UUID, body: HabitUpdate, principal: ApiPrincipal, w: WiringDep
) -> Habit:
    return await controller.update_habit(w.habits, principal, habit_id, body)


@router.delete(
    "/{habit_id}",
    operation_id="archiveHabit",
    responses=problems(P.unauthenticated, P.not_found, P.invalid),
)
async def archive_habit(habit_id: UUID, principal: ApiPrincipal, w: WiringDep) -> Habit:
    """Archive a habit from the next day."""
    return await controller.archive_habit(w.habits, principal, habit_id)
