"""`POST /dev/token`: a dev identity token for an email (TDD §5.10)."""

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

router = APIRouter()


class DevTokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str = Field(min_length=3, pattern=r"^[^@\s]+@[^@\s]+$")


class DevToken(BaseModel):
    identity_token: str


@router.post("/token")
async def issue_token(body: DevTokenRequest, request: Request) -> DevToken:
    """A token that `POST /v1/auth/session` accepts in development and tests."""
    tokens = request.app.state.wiring.dev_tokens
    return DevToken(identity_token=tokens.issue(body.email))
