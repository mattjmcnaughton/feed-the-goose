"""Maps the auth DTOs to the auth service and back."""

from feed_the_goose.controllers.me import user_dto
from feed_the_goose.dtos import auth as dto
from feed_the_goose.dtos.errors import FieldError, ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.accounts import AccountService
from feed_the_goose.services.auth import (
    AuthService,
    CredentialKind,
    InvalidTimeZoneError,
    NotAdmittedError,
    Principal,
    SessionNotFoundError,
    UnauthenticatedError,
)


async def create_session(
    auth: AuthService, accounts: AccountService, body: dto.SessionCreate
) -> dto.SessionCreated:
    try:
        signed_in = await auth.sign_in(
            body.auth0_access_token, body.time_zone, body.device_name
        )
        # The same user as GET /v1/me, with the day settings of the current day.
        account = await accounts.get(
            Principal(signed_in.user.id, CredentialKind.session, signed_in.session.id)
        )
    except UnauthenticatedError:
        raise ProblemError(ProblemType.unauthenticated) from None
    except NotAdmittedError:
        raise ProblemError(ProblemType.identity_not_admitted) from None
    except InvalidTimeZoneError:
        raise ProblemError(
            ProblemType.invalid,
            errors=[FieldError(field="time_zone", message="Value is not valid")],
        ) from None
    return dto.SessionCreated(
        session_token=signed_in.token,
        expires_at=signed_in.session.expires_at,
        user=user_dto(account),
    )


async def list_sessions(auth: AuthService, principal: Principal) -> list[dto.Session]:
    found = await auth.list_sessions(principal)
    return [
        dto.Session(
            id=s.id,
            device_name=s.device_name,
            created_at=s.created_at,
            last_used_at=s.last_used_at,
            current=s.id == found.current,
        )
        for s in found.sessions
    ]


async def delete_session(
    auth: AuthService, principal: Principal, session_id: str
) -> None:
    try:
        await auth.delete_session(principal, session_id)
    except SessionNotFoundError:
        raise ProblemError(ProblemType.not_found) from None
