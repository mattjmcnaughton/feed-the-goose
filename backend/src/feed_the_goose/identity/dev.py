"""The development sign-in and its guard (TDD §5.6, API spec "Credentials").

The server signs dev identity tokens with its own key, made when it starts, so a
token works until the server restarts. `POST /dev/token` issues them.
"""

from datetime import timedelta

from joserfc import jwt
from joserfc.jwk import OctKey

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.identity import VerifiedIdentity
from feed_the_goose.identity.claims import verify_jwt

ISSUER = "urn:dev-sign-in"
LIFETIME = timedelta(minutes=10)


class DevelopmentGuardError(RuntimeError):
    """The dev sign-in or the /dev routes are enabled in production."""


def check_development_guard(settings: Settings) -> None:
    """Refuse to start in production with the dev sign-in or the /dev routes on."""
    if settings.env == "production" and (
        settings.dev_sign_in_enabled or settings.dev_routes_enabled
    ):
        raise DevelopmentGuardError(
            "ENV=production with DEV_SIGN_IN_ENABLED or DEV_ROUTES_ENABLED set: "
            "the development sign-in and /dev routes are refused in production."
        )


class DevIdentityTokens:
    """Issues dev identity tokens and verifies them."""

    def __init__(self, *, audience: str, clock: Clock) -> None:
        self._audience = audience
        self._clock = clock
        self._key = OctKey.generate_key(256)

    def issue(self, email: str) -> str:
        email = email.strip().lower()
        now = self._clock.now()
        claims = {
            "iss": ISSUER,
            "aud": self._audience,
            "sub": f"dev|{email}",
            "email": email,
            "email_verified": True,
            "iat": int(now.timestamp()),
            "exp": int((now + LIFETIME).timestamp()),
        }
        return jwt.encode({"alg": "HS256"}, claims, self._key)

    async def verify(self, token: str) -> VerifiedIdentity:
        return verify_jwt(
            token,
            self._key,
            algorithms=["HS256"],
            issuer=ISSUER,
            audience=self._audience,
            clock=self._clock,
        )
