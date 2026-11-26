"""The Auth0 verifier against a fake issuer that serves its own keys (TDD §5.6).

No test calls Auth0: the issuer is an httpx transport in this process.
"""

from datetime import UTC, datetime, timedelta

import httpx
import pytest
from joserfc import jwt
from joserfc.jwk import KeySet, RSAKey

from feed_the_goose.clock import FixedClock
from feed_the_goose.identity import InvalidIdentityTokenError, VerifiedIdentity
from feed_the_goose.identity.auth0 import Auth0Verifier

pytestmark = pytest.mark.anyio

ISSUER = "https://fake-tenant.example.com/"
AUDIENCE = "https://feed-the-goose.mattjmcnaughton.com/v1"
NOW = datetime(2026, 11, 26, 15, tzinfo=UTC)


class FakeIssuer:
    def __init__(self) -> None:
        self.key = RSAKey.generate_key(2048, parameters={"kid": "key-1"})
        self.jwks_requests = 0

    def handler(self, request: httpx.Request) -> httpx.Response:
        assert str(request.url) == ISSUER + ".well-known/jwks.json"
        self.jwks_requests += 1
        return httpx.Response(200, json=KeySet([self.key]).as_dict())

    def token(self, key: RSAKey | None = None, **overrides) -> str:
        key = key or self.key
        claims = {
            "iss": ISSUER,
            "aud": AUDIENCE,
            "sub": "auth0|abc123",
            "email": "Matt@Example.com",
            "email_verified": True,
            "iat": int(NOW.timestamp()),
            "exp": int((NOW + timedelta(hours=1)).timestamp()),
        } | overrides
        return jwt.encode({"alg": "RS256", "kid": key.kid}, claims, key)


@pytest.fixture
def issuer() -> FakeIssuer:
    return FakeIssuer()


@pytest.fixture
def clock() -> FixedClock:
    return FixedClock(NOW)


@pytest.fixture
async def verifier(issuer: FakeIssuer, clock: FixedClock):
    http = httpx.AsyncClient(transport=httpx.MockTransport(issuer.handler))
    yield Auth0Verifier(issuer=ISSUER, audience=AUDIENCE, clock=clock, http=http)
    await http.aclose()


async def test_a_good_token_passes(verifier, issuer):
    identity = await verifier.verify(issuer.token())

    assert identity == VerifiedIdentity(
        subject="auth0|abc123", email="matt@example.com", email_verified=True
    )


async def test_an_audience_list_containing_ours_passes(verifier, issuer):
    token = issuer.token(aud=[AUDIENCE, "https://fake-tenant.example.com/userinfo"])

    assert (await verifier.verify(token)).subject == "auth0|abc123"


@pytest.mark.parametrize(
    "claims",
    [
        pytest.param({"aud": "https://someone-else.example.com"}, id="wrong-audience"),
        pytest.param({"iss": "https://evil.example.com/"}, id="wrong-issuer"),
        pytest.param({"exp": int(NOW.timestamp()) - 1}, id="expired"),
        pytest.param({"exp": int(NOW.timestamp())}, id="expires-now"),
        pytest.param({"email": None}, id="no-email"),
    ],
)
async def test_a_bad_claim_fails(verifier, issuer, claims):
    token = issuer.token(**{k: v for k, v in claims.items() if v is not None})
    if claims.get("email", "") is None:
        token = issuer.token(email="")

    with pytest.raises(InvalidIdentityTokenError):
        await verifier.verify(token)


async def test_a_bad_signature_fails(verifier, issuer):
    # Signed by another key that claims the issuer's key ID.
    impostor = RSAKey.generate_key(2048, parameters={"kid": "key-1"})

    with pytest.raises(InvalidIdentityTokenError):
        await verifier.verify(issuer.token(key=impostor))


async def test_a_tampered_payload_fails(verifier, issuer):
    header, _, signature = issuer.token().split(".")
    _, payload, _ = issuer.token(sub="auth0|someone-else").split(".")

    with pytest.raises(InvalidIdentityTokenError):
        await verifier.verify(f"{header}.{payload}.{signature}")


async def test_an_hs256_token_signed_with_the_public_key_fails(verifier, issuer):
    # Algorithm confusion: an HMAC keyed with the issuer's public key. Built by hand,
    # because joserfc refuses to make one.
    import base64
    import hashlib
    import hmac
    import json

    def b64(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    header = b64(json.dumps({"alg": "HS256", "kid": "key-1"}).encode())
    claims = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "sub": "x",
        "email": "a@b.c",
        "exp": int(NOW.timestamp()) + 60,
    }
    payload = b64(json.dumps(claims).encode())
    secret = issuer.key.as_pem(private=False)
    mac = hmac.new(secret, f"{header}.{payload}".encode(), hashlib.sha256).digest()

    with pytest.raises(InvalidIdentityTokenError):
        await verifier.verify(f"{header}.{payload}.{b64(mac)}")


async def test_garbage_fails(verifier):
    with pytest.raises(InvalidIdentityTokenError):
        await verifier.verify("not.a.jwt")


async def test_a_rotated_key_is_fetched_once_and_then_cached(verifier, issuer, clock):
    await verifier.verify(issuer.token())
    issuer.key = RSAKey.generate_key(2048, parameters={"kid": "key-2"})
    clock.set(NOW + timedelta(minutes=1))

    await verifier.verify(issuer.token())
    await verifier.verify(issuer.token())

    assert issuer.jwks_requests == 2


async def test_an_unreachable_issuer_fails_the_token_not_the_request(issuer):
    def down(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down", request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(down)) as http:
        verifier = Auth0Verifier(
            issuer=ISSUER, audience=AUDIENCE, clock=FixedClock(NOW), http=http
        )
        with pytest.raises(InvalidIdentityTokenError):
            await verifier.verify(issuer.token())


async def test_an_issuer_answering_garbage_fails_the_token():
    def garbage(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="<html>")

    async with httpx.AsyncClient(transport=httpx.MockTransport(garbage)) as http:
        verifier = Auth0Verifier(
            issuer=ISSUER, audience=AUDIENCE, clock=FixedClock(NOW), http=http
        )
        with pytest.raises(InvalidIdentityTokenError):
            await verifier.verify(FakeIssuer().token())


async def test_unknown_key_ids_refetch_at_most_once_a_minute(verifier, issuer, clock):
    await verifier.verify(issuer.token())
    stranger = RSAKey.generate_key(2048, parameters={"kid": "unknown"})

    for seconds in (0, 30, 59, 60, 61, 119):
        clock.set(NOW + timedelta(seconds=seconds))
        with pytest.raises(InvalidIdentityTokenError):
            await verifier.verify(issuer.token(key=stranger))

    # The first fetch at 0 s, then one at 60 s; 119 s is still within its minute.
    assert issuer.jwks_requests == 2
