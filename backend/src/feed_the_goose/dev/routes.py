"""The /dev routes. Registered only in development and tests (TDD §5.6, §5.10).

Tickets add their own registration lines here and nothing else.
"""

from fastapi import APIRouter

from feed_the_goose.config import Settings
from feed_the_goose.dev import pushes, seed, token


def router(settings: Settings) -> APIRouter | None:
    """The /dev router, or None when the /dev routes are off."""
    if settings.env == "production" or not settings.dev_routes_enabled:
        return None
    dev = APIRouter(prefix="/dev", tags=["dev"], include_in_schema=False)
    if settings.dev_sign_in_enabled:
        dev.include_router(token.router)
    dev.include_router(seed.router)
    dev.include_router(pushes.router)
    return dev
