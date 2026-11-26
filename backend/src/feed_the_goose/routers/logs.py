"""Logs (API spec "Logs").

A stub from T02: each route answers 501 `not_implemented` until T06 lands.
"""

from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query

from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.logs import Log, LogCreate, LogResult
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/logs", tags=["logs"])


@router.post(
    "",
    status_code=201,
    operation_id="createLog",
    responses={
        200: {"model": LogResult, "description": "A log with this ID already existed"},
        **problems(P.unauthenticated, P.not_found, P.day_settled, P.invalid),
    },
)
async def create_log(body: LogCreate) -> LogResult:
    """Log a habit. Sending the same ID again is safe."""
    raise not_implemented()


@router.delete(
    "/{log_id}",
    operation_id="undoLog",
    responses=problems(P.unauthenticated, P.not_found, P.day_settled, P.invalid),
)
async def undo_log(log_id: UUID) -> LogResult:
    raise not_implemented()


@router.get(
    "",
    operation_id="listLogs",
    responses=problems(P.unauthenticated, P.invalid),
)
async def list_logs(day: Annotated[date, Query(alias="date")]) -> list[Log]:
    """A day's logs, newest first, including undone ones."""
    raise not_implemented()
