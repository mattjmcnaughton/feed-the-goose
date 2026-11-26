"""Sign-in and app sessions (API spec "Auth")."""

from uuid import UUID

from pydantic import Field

from feed_the_goose.dtos.common import Dto, Instant, RequestDto
from feed_the_goose.dtos.me import User


class SessionCreate(RequestDto):
    """An identity token to swap for an app session."""

    auth0_access_token: str = Field(min_length=1)
    time_zone: str = Field(
        min_length=1, description="Used only when the account is created."
    )
    device_name: str = Field(min_length=1)


class SessionCreated(Dto):
    """A new app session. The token is returned this once only."""

    session_token: str
    expires_at: Instant
    user: User


class Session(Dto):
    """An app session. `current` marks the one making the request."""

    id: UUID
    device_name: str
    created_at: Instant
    last_used_at: Instant
    current: bool
