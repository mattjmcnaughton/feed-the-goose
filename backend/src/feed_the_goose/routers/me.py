"""The signed-in user (API spec "Me")."""

from typing import Annotated

from fastapi import APIRouter, Depends, Response

from feed_the_goose.controllers import me as controller
from feed_the_goose.deps import ApiPrincipal, SessionPrincipal, wiring
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.me import User, UserUpdate
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

router = APIRouter(prefix="/v1", tags=["me"])

WiringDep = Annotated[Wiring, Depends(wiring)]


@router.get("/me", operation_id="getMe", responses=problems(P.unauthenticated))
async def get_me(principal: ApiPrincipal, w: WiringDep) -> User:
    return await controller.get_me(w.accounts, principal)


@router.patch(
    "/me",
    operation_id="updateMe",
    responses=problems(P.unauthenticated, P.invalid),
)
async def update_me(body: UserUpdate, principal: ApiPrincipal, w: WiringDep) -> User:
    """Change settings. Changes to the day take effect from the next day."""
    return await controller.update_me(w.accounts, principal, body)


@router.delete(
    "/me",
    status_code=204,
    response_class=Response,
    operation_id="deleteMe",
    responses=problems(P.unauthenticated),
)
async def delete_me(principal: SessionPrincipal, w: WiringDep) -> None:
    """Delete the account and all of its data."""
    await controller.delete_me(w.accounts, principal)
