"""Chase history (API spec "Chase and history")."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from feed_the_goose.controllers import days as controller
from feed_the_goose.deps import ApiPrincipal, session_or_api_key, wiring
from feed_the_goose.dtos.chase import DaySummary
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/days", tags=["chase"], dependencies=[Depends(session_or_api_key)]
)


@router.get(
    "",
    operation_id="listDays",
    responses=problems(P.unauthenticated, P.invalid),
)
async def list_days(
    first: Annotated[date, Query(alias="from")],
    last: Annotated[date, Query(alias="to")],
    principal: ApiPrincipal,
    w: WiringDep,
) -> list[DaySummary]:
    """Each day's result from `from` to `to`, inclusive."""
    return await controller.list_days(w.chase, principal.user_id, first, last)
