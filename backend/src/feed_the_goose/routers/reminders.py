"""Reminder preferences (API spec "Devices and push").

A stub from T02: each route answers 501 `not_implemented` until T09 lands.
"""

from fastapi import APIRouter, Depends

from feed_the_goose.deps import session_or_api_key
from feed_the_goose.dtos.devices import Reminders
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(
    prefix="/v1/me/reminders",
    tags=["reminders"],
    dependencies=[Depends(session_or_api_key)],
)


@router.get("", operation_id="getReminders", responses=problems(P.unauthenticated))
async def get_reminders() -> Reminders:
    raise not_implemented()


@router.put(
    "",
    operation_id="updateReminders",
    responses=problems(P.unauthenticated, P.invalid),
)
async def update_reminders(body: Reminders) -> Reminders:
    raise not_implemented()
