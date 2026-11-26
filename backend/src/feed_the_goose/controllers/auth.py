"""Maps the auth DTOs to the auth service and back."""

from zoneinfo import ZoneInfo

from feed_the_goose.clock import Clock
from feed_the_goose.dtos import auth as dto
from feed_the_goose.dtos.errors import FieldError, ProblemType
from feed_the_goose.dtos.me import PendingDay, User
from feed_the_goose.errors import ProblemError
from feed_the_goose.models import DaySettings
from feed_the_goose.models import User as UserRow
from feed_the_goose.services.auth import (
    AuthService,
    InvalidTimeZoneError,
    NotAdmittedError,
    Principal,
    SessionNotFoundError,
    UnauthenticatedError,
)


async def create_session(
    auth: AuthService, clock: Clock, body: dto.SessionCreate
) -> dto.SessionCreated:
    try:
        signed_in = await auth.sign_in(
            body.auth0_access_token, body.time_zone, body.device_name
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
        user=user_dto(signed_in.user, signed_in.day_settings, clock),
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


def user_dto(user: UserRow, day_settings: list[DaySettings], clock: Clock) -> User:
    """The User DTO. The day fields are the settings in effect today; a later row
    is `pending`. `day_settings` is oldest first."""
    latest = day_settings[-1]
    today = clock.now().astimezone(ZoneInfo(latest.time_zone)).date()
    current = next(s for s in reversed(day_settings) if s.effective_from <= today)
    pending = latest if latest.effective_from > today else None
    return User(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        pursuer=user.pursuer,  # type: ignore[arg-type]  # validated by the DTO
        time_zone=current.time_zone,
        day_start=current.day_start.strftime("%H:%M"),
        day_end=current.day_end.strftime("%H:%M"),
        pending=None
        if pending is None
        else PendingDay(
            effective_from=pending.effective_from,
            time_zone=pending.time_zone,
            day_start=pending.day_start.strftime("%H:%M"),
            day_end=pending.day_end.strftime("%H:%M"),
        ),
        created_at=user.created_at,
    )
