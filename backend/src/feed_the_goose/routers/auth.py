"""Sign-in and app sessions (API spec "Auth")."""

from typing import Annotated

from fastapi import APIRouter, Depends, Path, Response

from feed_the_goose.controllers import auth as controller
from feed_the_goose.deps import SessionPrincipal, wiring
from feed_the_goose.dtos.auth import Session, SessionCreate, SessionCreated
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

router = APIRouter(prefix="/v1/auth", tags=["auth"])

WiringDep = Annotated[Wiring, Depends(wiring)]


@router.post(
    "/session",
    status_code=201,
    operation_id="createSession",
    responses=problems(P.unauthenticated, P.identity_not_admitted, P.invalid),
)
async def create_session(body: SessionCreate, w: WiringDep) -> SessionCreated:
    """Swap an identity token for an app session. Creates the account on first use."""
    return await controller.create_session(w.auth, w.clock, body)


@router.get(
    "/sessions", operation_id="listSessions", responses=problems(P.unauthenticated)
)
async def list_sessions(principal: SessionPrincipal, w: WiringDep) -> list[Session]:
    return await controller.list_sessions(w.auth, principal)


@router.delete(
    "/sessions/{session_id}",
    status_code=204,
    response_class=Response,
    operation_id="deleteSession",
    responses=problems(P.unauthenticated, P.not_found),
)
async def delete_session(
    session_id: Annotated[
        str, Path(description="A session's ID, or `current` to sign out.")
    ],
    principal: SessionPrincipal,
    w: WiringDep,
) -> None:
    await controller.delete_session(w.auth, principal, session_id)
