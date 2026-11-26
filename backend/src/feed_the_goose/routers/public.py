"""The published profile, readable without signing in (API spec "Public profile").

Neither route reads a credential or sets a cookie, both re-check publication on every
request, and both answer `Cache-Control: no-store` (TDD §5.8). `page_router` serves
`/{handle}` and is registered last, so it never shadows another route.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import HTMLResponse

from feed_the_goose import profile as page
from feed_the_goose.controllers import profile as controller
from feed_the_goose.deps import wiring
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.dtos.profile import PublicProfile
from feed_the_goose.errors import ProblemError, problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(prefix="/v1/profiles", tags=["profile"])
page_router = APIRouter(include_in_schema=False)


@router.get(
    "/{handle}",
    operation_id="getPublicProfile",
    responses=problems(P.not_found),
)
async def get_public_profile(
    handle: str, response: Response, w: WiringDep
) -> PublicProfile:
    """A published profile. 404 when it is not public."""
    response.headers.update(controller.NO_STORE)
    return await controller.published(w.profile, handle)


@page_router.get("/{handle}")
async def get_profile_page(handle: str, request: Request, w: WiringDep) -> HTMLResponse:
    """The same profile as a self-contained HTML page."""
    try:
        found = await controller.published(w.profile, handle)
    except ProblemError:
        return HTMLResponse(
            page.NOT_FOUND, status_code=404, headers=controller.NO_STORE
        )
    address = f"{request.url.netloc}/{handle}"
    html = page.render(found, address, full_lead=w.settings.starting_lead)
    return HTMLResponse(html, headers=controller.NO_STORE)
