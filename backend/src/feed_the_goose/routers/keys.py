"""API and MCP keys (API spec "Keys"). App session only."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Response

from feed_the_goose.controllers import keys as controller
from feed_the_goose.deps import SessionPrincipal, session_only, wiring
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.keys import Key, KeyCreate, KeyCreated
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/me/keys", tags=["keys"], dependencies=[Depends(session_only)]
)


@router.get("", operation_id="listKeys", responses=problems(P.unauthenticated))
async def list_keys(principal: SessionPrincipal, w: WiringDep) -> list[Key]:
    return await controller.list_keys(w.keys, principal)


@router.post(
    "",
    status_code=201,
    operation_id="createKey",
    responses=problems(P.unauthenticated, P.invalid),
)
async def create_key(
    body: KeyCreate, principal: SessionPrincipal, w: WiringDep
) -> KeyCreated:
    """Create a key. Its secret is returned this once only."""
    return await controller.create_key(w.keys, principal, body)


@router.delete(
    "/{key_id}",
    status_code=204,
    response_class=Response,
    operation_id="deleteKey",
    responses=problems(P.unauthenticated, P.not_found, P.invalid),
)
async def delete_key(key_id: UUID, principal: SessionPrincipal, w: WiringDep) -> None:
    await controller.delete_key(w.keys, principal, key_id)
