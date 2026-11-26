"""Shared checks for identity tokens (JWTs)."""

from typing import Any

from joserfc import jwt
from joserfc.errors import JoseError
from joserfc.jwk import KeyFlexible

from feed_the_goose.clock import Clock
from feed_the_goose.identity import InvalidIdentityTokenError, VerifiedIdentity


def verify_jwt(
    token: str,
    key: KeyFlexible,
    *,
    algorithms: list[str],
    issuer: str,
    audience: str,
    clock: Clock,
) -> VerifiedIdentity:
    """Check the signature, issuer, audience and expiry, and read the identity."""
    try:
        claims: dict[str, Any] = jwt.decode(token, key, algorithms=algorithms).claims
        jwt.JWTClaimsRegistry(
            now=int(clock.now().timestamp()),
            iss={"essential": True, "value": issuer},
            aud={"essential": True, "value": audience},
            exp={"essential": True},
            sub={"essential": True},
        ).validate(claims)
    except (JoseError, ValueError) as error:
        raise InvalidIdentityTokenError from error
    email = claims.get("email")
    if not isinstance(email, str) or not email:
        raise InvalidIdentityTokenError
    return VerifiedIdentity(
        subject=str(claims["sub"]),
        email=email.strip().lower(),
        email_verified=claims.get("email_verified") is True,
    )
