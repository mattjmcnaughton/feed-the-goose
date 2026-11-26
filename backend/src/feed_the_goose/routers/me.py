"""The signed-in user (API spec "Me").

A stub from T02: each route answers 501 `not_implemented` until T05 lands.
"""

from fastapi import APIRouter, Depends, Response

from feed_the_goose.deps import session_only, session_or_api_key
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.me import User, UserUpdate
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1", tags=["me"])


@router.get(
    "/me",
    operation_id="getMe",
    responses=problems(P.unauthenticated),
    dependencies=[Depends(session_or_api_key)],
)
async def get_me() -> User:
    raise not_implemented()


@router.patch(
    "/me",
    operation_id="updateMe",
    dependencies=[Depends(session_or_api_key)],
    responses=problems(P.unauthenticated, P.invalid),
)
async def update_me(body: UserUpdate) -> User:
    """Change settings. Changes to the day take effect from the next day."""
    raise not_implemented()


@router.delete(
    "/me",
    status_code=204,
    response_class=Response,
    operation_id="deleteMe",
    dependencies=[Depends(session_only)],
    responses=problems(P.unauthenticated),
)
async def delete_me() -> None:
    """Delete the account and all of its data."""
    raise not_implemented()
