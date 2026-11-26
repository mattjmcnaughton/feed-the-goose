"""Maps the chase service to the Chase DTO. Steps are rounded here and nowhere else:
to one decimal place, and `steps_per_hour` to two (TDD §5.3)."""

from fractions import Fraction
from math import floor
from uuid import UUID

from feed_the_goose.dtos import chase as dto
from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.chase import ChaseService, ChaseView, NoChaseError


def rounded(value: Fraction, places: int = 1) -> float:
    """`value` rounded half up to `places` decimal places."""
    scale = 10**places
    return floor(value * scale + Fraction(1, 2)) / scale


async def get_today(service: ChaseService, user_id: UUID) -> dto.Chase:
    try:
        view = await service.today(user_id)
    except NoChaseError:
        raise ProblemError(ProblemType.no_chase) from None
    return chase_dto(view)


def chase_dto(view: ChaseView) -> dto.Chase:
    record, state = view.record, view.state
    progress = {p.habit_id: p for p in state.habits}
    return dto.Chase(
        date=record.row.date,
        pursuer=view.pursuer,  # type: ignore[arg-type]  # validated by the DTO
        state=dto.ChaseState(state.state.value),
        as_of=state.at,
        lead=rounded(state.lead),
        starting_lead=rounded(record.row.starting_lead),
        earned=rounded(state.earned),
        walked=rounded(state.walked),
        steps_per_hour=rounded(record.window.steps_per_hour, 2),
        day_starts_at=record.row.starts_at,
        day_ends_at=record.row.ends_at,
        next_day_starts_at=record.next_day_starts_at,
        caught_at=state.caught_at,
        habits=[
            dto.ChaseHabit(
                habit_id=h.habit.id,
                name=h.habit.name,
                unit=h.habit.unit,
                target=h.target,
                chunk=h.habit.chunk,
                logged=progress[str(h.habit.id)].logged,
                steps=rounded(progress[str(h.habit.id)].steps),
                done=progress[str(h.habit.id)].done,
            )
            for h in record.habits
        ],
        streak=dto.Streak(complete_days=view.complete_days, stage=view.stage),
    )
