"""The published profile, readable without signing in (API spec "Public profile").

A stub from T02: each route answers 501 `not_implemented` until T08 lands.
"""

from fastapi import APIRouter

from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.profile import PublicProfile
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/profiles", tags=["profile"])


@router.get(
    "/{handle}",
    operation_id="getPublicProfile",
    responses=problems(P.not_found),
)
async def get_public_profile(handle: str) -> PublicProfile:
    """A published profile. 404 when it is not public."""
    raise not_implemented()
