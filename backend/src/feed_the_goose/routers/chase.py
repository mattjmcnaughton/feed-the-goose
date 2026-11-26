"""The current day's chase (API spec "Chase and history").

A stub from T02: each route answers 501 `not_implemented` until T06 lands.
"""

from fastapi import APIRouter, Depends

from feed_the_goose.deps import session_or_api_key
from feed_the_goose.dtos.chase import Chase
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(
    prefix="/v1/chase", tags=["chase"], dependencies=[Depends(session_or_api_key)]
)


@router.get(
    "/today",
    operation_id="getChaseToday",
    responses=problems(P.unauthenticated, P.no_chase),
)
async def get_chase_today() -> Chase:
    """The current day's chase; during the night, the day that just ended."""
    raise not_implemented()
