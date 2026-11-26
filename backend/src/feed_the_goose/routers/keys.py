"""API and MCP keys (API spec "Keys").

A stub from T02: each route answers 501 `not_implemented` until T07 lands.
"""

from uuid import UUID

from fastapi import APIRouter, Response

from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.keys import Key, KeyCreate, KeyCreated
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/me/keys", tags=["keys"])


@router.get("", operation_id="listKeys", responses=problems(P.unauthenticated))
async def list_keys() -> list[Key]:
    raise not_implemented()


@router.post(
    "",
    status_code=201,
    operation_id="createKey",
    responses=problems(P.unauthenticated, P.invalid),
)
async def create_key(body: KeyCreate) -> KeyCreated:
    """Create a key. Its secret is returned this once only."""
    raise not_implemented()


@router.delete(
    "/{key_id}",
    status_code=204,
    response_class=Response,
    operation_id="deleteKey",
    responses=problems(P.unauthenticated, P.not_found, P.invalid),
)
async def delete_key(key_id: UUID) -> None:
    raise not_implemented()
