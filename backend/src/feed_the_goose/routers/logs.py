"""Logs (API spec "Logs")."""

from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response

from feed_the_goose.controllers import logs as controller
from feed_the_goose.deps import ApiPrincipal, session_or_api_key, wiring
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.logs import Log, LogCreate, LogResult
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/logs", tags=["logs"], dependencies=[Depends(session_or_api_key)]
)


@router.post(
    "",
    status_code=201,
    operation_id="createLog",
    responses={
        200: {"model": LogResult, "description": "A log with this ID already existed"},
        **problems(P.unauthenticated, P.not_found, P.day_settled, P.invalid),
    },
)
async def create_log(
    body: LogCreate, principal: ApiPrincipal, w: WiringDep, response: Response
) -> LogResult:
    """Log a habit. Sending the same ID again is safe."""
    result, created = await controller.create_log(w.logs, principal.user_id, body)
    if not created:
        response.status_code = 200
    return result


@router.delete(
    "/{log_id}",
    operation_id="undoLog",
    responses=problems(P.unauthenticated, P.not_found, P.day_settled, P.invalid),
)
async def undo_log(log_id: UUID, principal: ApiPrincipal, w: WiringDep) -> LogResult:
    return await controller.undo_log(w.logs, principal.user_id, log_id)


@router.get(
    "",
    operation_id="listLogs",
    responses=problems(P.unauthenticated, P.invalid),
)
async def list_logs(
    day: Annotated[date, Query(alias="date")], principal: ApiPrincipal, w: WiringDep
) -> list[Log]:
    """A day's logs, newest first, including undone ones."""
    return await controller.list_logs(w.logs, principal.user_id, day)
