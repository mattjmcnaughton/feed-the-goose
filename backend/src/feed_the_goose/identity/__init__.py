"""Identity: verifying the token an identity provider issued (TDD §5.6)."""

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class VerifiedIdentity:
    """Who a verified identity token names."""

    subject: str
    email: str
    email_verified: bool


class InvalidIdentityTokenError(Exception):
    """The token is malformed, unsigned by a trusted key, expired, or for someone
    else. Carries no detail, so nothing about the token reaches a response."""


class IdentityVerifier(Protocol):
    async def verify(self, token: str) -> VerifiedIdentity:
        """Return the token's identity, or raise `InvalidIdentityTokenError`."""
        ...
