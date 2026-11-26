"""Reminder preferences (API spec "Devices and push")."""

from typing import Annotated

from fastapi import APIRouter, Depends

from feed_the_goose.controllers import reminders as controller
from feed_the_goose.deps import ApiPrincipal, session_or_api_key, wiring
from feed_the_goose.dtos.devices import Reminders
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/me/reminders",
    tags=["reminders"],
    dependencies=[Depends(session_or_api_key)],
)


@router.get("", operation_id="getReminders", responses=problems(P.unauthenticated))
async def get_reminders(principal: ApiPrincipal, w: WiringDep) -> Reminders:
    return await controller.get_reminders(w.reminders, principal)


@router.put(
    "",
    operation_id="updateReminders",
    responses=problems(P.unauthenticated, P.invalid),
)
async def update_reminders(
    body: Reminders, principal: ApiPrincipal, w: WiringDep
) -> Reminders:
    return await controller.update_reminders(w.reminders, principal, body)
