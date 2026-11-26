"""The current day's chase (API spec "Chase and history")."""

from typing import Annotated

from fastapi import APIRouter, Depends

from feed_the_goose.controllers import chase as controller
from feed_the_goose.deps import ApiPrincipal, session_or_api_key, wiring
from feed_the_goose.dtos.chase import Chase
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/chase", tags=["chase"], dependencies=[Depends(session_or_api_key)]
)


@router.get(
    "/today",
    operation_id="getChaseToday",
    responses=problems(P.unauthenticated, P.no_chase),
)
async def get_chase_today(principal: ApiPrincipal, w: WiringDep) -> Chase:
    """The current day's chase; during the night, the day that just ended."""
    return await controller.get_today(w.chase, principal.user_id)
