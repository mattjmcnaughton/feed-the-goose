"""Maps the chase history to DaySummary DTOs."""

from datetime import date
from uuid import UUID

from feed_the_goose.controllers.chase import rounded
from feed_the_goose.dtos import chase as dto
from feed_the_goose.dtos.errors import FieldError, ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.chase import ChaseService, InvalidRangeError


async def list_days(
    service: ChaseService, user_id: UUID, first: date, last: date
) -> list[dto.DaySummary]:
    try:
        results = await service.history(user_id, first, last)
    except InvalidRangeError:
        raise ProblemError(
            ProblemType.invalid,
            errors=[FieldError(field="to", message="Value is not valid")],
        ) from None
    return [
        dto.DaySummary(
            date=r.date,
            pursuer=r.pursuer,  # type: ignore[arg-type]  # validated by the DTO
            result=dto.ChaseState(r.result.value),
            end_lead=None if r.end_lead is None else rounded(r.end_lead),
            complete_days=r.complete_days,
        )
        for r in results
    ]
