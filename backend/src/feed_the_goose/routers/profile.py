"""Profile settings (API spec "Public profile").

A stub from T02: each route answers 501 `not_implemented` until T08 lands.
"""

from fastapi import APIRouter

from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.profile import ProfileSettings, ProfileUpdate
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/me/profile", tags=["profile"])


@router.get(
    "", operation_id="getProfileSettings", responses=problems(P.unauthenticated)
)
async def get_profile_settings() -> ProfileSettings:
    raise not_implemented()


@router.put(
    "",
    operation_id="updateProfileSettings",
    responses=problems(P.unauthenticated, P.handle_taken, P.invalid),
)
async def update_profile_settings(body: ProfileUpdate) -> ProfileSettings:
    raise not_implemented()
