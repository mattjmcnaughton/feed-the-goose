"""The Auth0 verifier (TDD §5.6). Tests run it against a fake issuer."""

from datetime import datetime, timedelta

import httpx
from joserfc import jws
from joserfc.errors import JoseError
from joserfc.jwk import KeySet

from feed_the_goose.clock import Clock
from feed_the_goose.identity import InvalidIdentityTokenError, VerifiedIdentity
from feed_the_goose.identity.claims import verify_jwt

REFETCH_AFTER = timedelta(minutes=1)


class Auth0Verifier:
    """Verifies RS256 tokens against the issuer's published keys.

    The keys are fetched from `<issuer>/.well-known/jwks.json` on first use, and
    fetched again when a token names a key ID they do not have (a rotated key), at
    most once a minute, so that made-up key IDs cannot flood the issuer. A failed
    fetch fails the token, never the request.
    The email comes from the token's `email` and `email_verified` claims.
    """

    def __init__(
        self, *, issuer: str, audience: str, clock: Clock, http: httpx.AsyncClient
    ) -> None:
        self._issuer = issuer
        self._audience = audience
        self._clock = clock
        self._http = http
        self._jwks_url = issuer.rstrip("/") + "/.well-known/jwks.json"
        self._keys: KeySet | None = None
        self._fetched_at: datetime | None = None

    async def verify(self, token: str) -> VerifiedIdentity:
        try:
            kid = jws.extract_compact(token.encode()).headers().get("kid")
        except (JoseError, ValueError) as error:
            raise InvalidIdentityTokenError from error
        if not kid:  # Auth0 always names its key; this is someone else's token.
            raise InvalidIdentityTokenError
        keys = self._keys
        if keys is None or kid not in {key.kid for key in keys}:
            keys = await self._refetch_keys()
        return verify_jwt(
            token,
            keys,
            algorithms=["RS256"],
            issuer=self._issuer,
            audience=self._audience,
            clock=self._clock,
        )

    async def _refetch_keys(self) -> KeySet:
        now = self._clock.now()
        if self._fetched_at is not None and now - self._fetched_at < REFETCH_AFTER:
            raise InvalidIdentityTokenError
        self._fetched_at = now
        try:
            response = await self._http.get(self._jwks_url)
            response.raise_for_status()
            self._keys = KeySet.import_key_set(response.json())
        except (httpx.HTTPError, JoseError, ValueError, TypeError) as error:
            raise InvalidIdentityTokenError from error
        return self._keys
