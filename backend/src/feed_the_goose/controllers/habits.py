"""Maps the habit DTOs to the habit service and back."""

from collections.abc import Generator
from contextlib import contextmanager
from uuid import UUID

from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.dtos.habits import Habit, HabitCreate, HabitUpdate
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.auth import Principal, UnauthenticatedError
from feed_the_goose.services.habits import (
    HabitChanges,
    HabitNotFoundError,
    HabitService,
    HabitView,
    TooManyHabitsError,
)


@contextmanager
def _problems(max_habits: int | None = None) -> Generator[None]:
    try:
        yield
    except UnauthenticatedError:
        raise ProblemError(ProblemType.unauthenticated) from None
    except HabitNotFoundError:
        raise ProblemError(ProblemType.not_found) from None
    except TooManyHabitsError:
        raise ProblemError(
            ProblemType.invalid, detail=f"A day can have at most {max_habits} habits."
        ) from None


async def list_habits(habits: HabitService, principal: Principal) -> list[Habit]:
    with _problems():
        return [_habit(v) for v in await habits.listed(principal)]


async def create_habit(
    habits: HabitService, principal: Principal, body: HabitCreate, max_habits: int
) -> Habit:
    with _problems(max_habits):
        return _habit(
            await habits.create(
                principal,
                name=body.name,
                unit=body.unit,
                target=body.target,
                chunk=body.chunk,
            )
        )


async def update_habit(
    habits: HabitService, principal: Principal, habit_id: UUID, body: HabitUpdate
) -> Habit:
    changes = HabitChanges(**body.model_dump(exclude_none=True))
    with _problems():
        return _habit(await habits.update(principal, habit_id, changes))


async def archive_habit(
    habits: HabitService, principal: Principal, habit_id: UUID
) -> Habit:
    with _problems():
        return _habit(await habits.archive(principal, habit_id))


def _habit(view: HabitView) -> Habit:
    h = view.habit
    return Habit(
        id=h.id,
        name=h.name,
        unit=h.unit,
        target=view.target,
        chunk=h.chunk,
        position=h.position,
        effective_from=h.effective_from,
        archived_from=h.archived_from,
    )
