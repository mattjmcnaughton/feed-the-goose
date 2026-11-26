"""Profile settings (API spec "Public profile")."""

from typing import Annotated

from fastapi import APIRouter, Depends

from feed_the_goose.controllers import profile as controller
from feed_the_goose.deps import ApiPrincipal, session_or_api_key, wiring
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.profile import ProfileSettings, ProfileUpdate
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/me/profile",
    tags=["profile"],
    dependencies=[Depends(session_or_api_key)],
)


@router.get(
    "", operation_id="getProfileSettings", responses=problems(P.unauthenticated)
)
async def get_profile_settings(
    principal: ApiPrincipal, w: WiringDep
) -> ProfileSettings:
    return await controller.get_settings(w.profile, principal.user_id)


@router.put(
    "",
    operation_id="updateProfileSettings",
    responses=problems(P.unauthenticated, P.handle_taken, P.invalid),
)
async def update_profile_settings(
    body: ProfileUpdate, principal: ApiPrincipal, w: WiringDep
) -> ProfileSettings:
    return await controller.update_settings(w.profile, principal.user_id, body)
