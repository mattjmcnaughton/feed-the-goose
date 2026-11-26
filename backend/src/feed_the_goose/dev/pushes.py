"""`GET /dev/pushes`: what the recording sender captured (TDD §5.9, §5.10)."""

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel

from feed_the_goose.repositories.push_jobs import PushJobRepository

router = APIRouter()


class RecordedPush(BaseModel):
    email: str
    installation_id: str
    payload: dict[str, Any]
    sent_at: datetime


@router.get("/pushes")
async def pushes(
    request: Request,
    email: str | None = None,
    limit: int = Query(default=50, ge=1, le=500),
) -> list[RecordedPush]:
    """Recorded pushes, newest first, optionally for one email. Each `payload` can
    be delivered to the simulator with `xcrun simctl push`."""
    wired = request.app.state.wiring
    async with wired.sessions() as db:
        found = await PushJobRepository(db).deliveries(
            None if email is None else email.strip().lower(), limit
        )
    return [
        RecordedPush(
            email=user_email,
            installation_id=d.installation_id,
            payload=d.payload,
            sent_at=d.sent_at,
        )
        for d, user_email in found
    ]
