"""`POST /dev/seed`: create or reset a user in a named scenario (TDD §5.10).

The user is the one the dev sign-in makes for the email, so signing in with
`POST /dev/token` reaches them. The email must still be in `ALLOWED_EMAILS`.
"""

from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from feed_the_goose.dev.scenarios import SCENARIOS, Seeding
from feed_the_goose.models import User
from feed_the_goose.repositories.users import UserRepository

router = APIRouter()


class SeedRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scenario: Literal["fresh", "demo", "caught-soon", "almost-complete"]
    email: str = Field(min_length=3, pattern=r"^[^@\s]+@[^@\s]+$")
    # For `caught-soon`: seconds from seeding until the catch.
    delay_seconds: int = Field(default=60, ge=1, le=3600)


class Seeded(BaseModel):
    email: str
    handle: str | None


@router.post("/seed")
async def seed(body: SeedRequest, request: Request) -> Seeded:
    """Seed the scenario for the email, deleting any user it already has."""
    wired = request.app.state.wiring
    email = body.email.strip().lower()
    now = wired.clock.now()
    async with wired.sessions.begin() as db:
        users = UserRepository(db)
        # The subject the dev sign-in gives this email.
        subject = f"dev|{email}"
        if (existing := await users.by_identity_subject(subject)) is not None:
            await users.delete(existing.id)
        user = await users.add(
            User(
                identity_subject=subject,
                email=email,
                display_name=email.split("@")[0],
                pursuer=wired.settings.pursuers[0],
                public=False,
                reminders_enabled=False,
                reminder_lead_below=wired.settings.reminder_lead_below,
                created_at=now,
            )
        )
        await SCENARIOS[body.scenario](
            Seeding(
                db=db,
                user=user,
                now=now,
                steps_per_day=wired.settings.steps_per_day,
                delay=timedelta(seconds=body.delay_seconds),
            )
        )
        return Seeded(email=email, handle=user.handle)
