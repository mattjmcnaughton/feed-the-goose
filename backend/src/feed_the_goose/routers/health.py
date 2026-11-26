"""Health check endpoints."""

from fastapi import APIRouter, Response
from sqlalchemy import text

from feed_the_goose.db import async_session

router = APIRouter(tags=["health"])


@router.get("/healthz")
async def healthz() -> dict[str, str]:
    """Liveness probe."""
    return {"status": "ok"}


@router.get("/readyz")
async def readyz(response: Response) -> dict[str, str]:
    """Readiness probe: 200 when the database answers, 503 otherwise."""
    try:
        async with async_session() as session:
            await session.execute(text("SELECT 1"))
    except Exception:
        response.status_code = 503
        return {"status": "not ready", "database": "unreachable"}
    return {"status": "ready"}
