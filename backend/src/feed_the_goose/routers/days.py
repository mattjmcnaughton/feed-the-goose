"""Chase history (API spec "Chase and history").

A stub from T02: each route answers 501 `not_implemented` until T06 lands.
"""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from feed_the_goose.deps import session_or_api_key
from feed_the_goose.dtos.chase import DaySummary
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import not_implemented, problems

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
) -> list[DaySummary]:
    """Each day's result from `from` to `to`, inclusive."""
    raise not_implemented()
