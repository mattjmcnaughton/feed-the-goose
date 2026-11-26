"""Maps the profile service to the profile DTOs. The JSON and the page are both built
from `published`, so the page can show nothing the JSON does not publish."""

from uuid import UUID

from feed_the_goose.controllers.chase import rounded
from feed_the_goose.dtos import profile as dto
from feed_the_goose.dtos.common import ChaseState
from feed_the_goose.dtos.errors import FieldError, ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.profile import (
    HandleReservedError,
    HandleTakenError,
    ProfileNotFoundError,
    ProfileService,
)

# Public responses are never cached by a browser or a proxy (TDD §5.8).
NO_STORE = {"Cache-Control": "no-store"}


async def get_settings(service: ProfileService, user_id: UUID) -> dto.ProfileSettings:
    found = await service.get_settings(user_id)
    return dto.ProfileSettings(handle=found.handle, public=found.public)


async def update_settings(
    service: ProfileService, user_id: UUID, body: dto.ProfileUpdate
) -> dto.ProfileSettings:
    try:
        found = await service.update_settings(user_id, body.handle, body.public)
    except HandleTakenError:
        raise ProblemError(ProblemType.handle_taken) from None
    except HandleReservedError:
        raise ProblemError(
            ProblemType.invalid,
            errors=[FieldError(field="handle", message="That handle is reserved")],
        ) from None
    return dto.ProfileSettings(handle=found.handle, public=found.public)


async def published(service: ProfileService, handle: str) -> dto.PublicProfile:
    try:
        found = await service.published(handle)
    except ProfileNotFoundError:
        raise ProblemError(ProblemType.not_found, headers=NO_STORE) from None
    return dto.PublicProfile(
        display_name=found.display_name,
        pursuer=found.pursuer,  # type: ignore[arg-type]  # validated by the DTO
        complete_days=found.complete_days,
        stage=found.stage,
        state=ChaseState(found.state.value),
        lead=rounded(found.lead),
        as_of=found.as_of,
        steps_per_hour=rounded(found.steps_per_hour, 2),
        caught_at=found.caught_at,
        days=[
            dto.ProfileDay(date=d.date, result=ChaseState(d.result.value))
            for d in found.days
        ],
    )
