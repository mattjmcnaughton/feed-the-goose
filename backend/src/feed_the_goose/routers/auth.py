"""Sign-in and app sessions (API spec "Auth").

A stub from T02: each route answers 501 `not_implemented` until T04 lands.
"""

from typing import Annotated

from fastapi import APIRouter, Path, Response

from feed_the_goose.dtos.auth import Session, SessionCreate, SessionCreated
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/auth", tags=["auth"])


@router.post(
    "/session",
    status_code=201,
    operation_id="createSession",
    responses=problems(P.unauthenticated, P.identity_not_admitted, P.invalid),
)
async def create_session(body: SessionCreate) -> SessionCreated:
    """Swap an identity token for an app session. Creates the account on first use."""
    raise not_implemented()


@router.get(
    "/sessions", operation_id="listSessions", responses=problems(P.unauthenticated)
)
async def list_sessions() -> list[Session]:
    raise not_implemented()


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
) -> None:
    raise not_implemented()
