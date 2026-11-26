"""The principal dependency: who is calling, and with which credential (TDD §5.6).

Each router declares the credential kinds it accepts, following the API spec's
Credentials table. A missing, unknown, expired or revoked credential, or one of the
wrong kind, is 401 `unauthenticated`.
"""

from collections.abc import Awaitable, Callable
from typing import Annotated

from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.auth import CredentialKind, Principal, UnauthenticatedError
from feed_the_goose.wiring import Wiring

_bearer = HTTPBearer(auto_error=False)


def unauthenticated() -> ProblemError:
    return ProblemError(
        ProblemType.unauthenticated, headers={"WWW-Authenticate": "Bearer"}
    )


def wiring(request: Request) -> Wiring:
    return request.app.state.wiring


def accepts(*kinds: CredentialKind) -> Callable[..., Awaitable[Principal]]:
    """A dependency that resolves the bearer credential, if it is one of `kinds`."""
    accepted = frozenset(kinds)

    async def principal(
        request: Request,
        credentials: Annotated[HTTPAuthorizationCredentials | None, Security(_bearer)],
    ) -> Principal:
        if credentials is None:
            raise unauthenticated()
        try:
            return await wiring(request).auth.authenticate(
                credentials.credentials, accepted
            )
        except UnauthenticatedError:
            raise unauthenticated() from None

    return principal


# The kinds each group of routes accepts (API spec "Credentials").
session_only = accepts(CredentialKind.session)
session_or_api_key = accepts(CredentialKind.session, CredentialKind.api)

SessionPrincipal = Annotated[Principal, Depends(session_only)]
ApiPrincipal = Annotated[Principal, Depends(session_or_api_key)]
