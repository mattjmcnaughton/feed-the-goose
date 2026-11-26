"""FastAPI application factory."""

from contextlib import asynccontextmanager

from fastapi import FastAPI

from feed_the_goose import errors
from feed_the_goose.logging import configure_logging
from feed_the_goose.routers import (
    auth,
    chase,
    days,
    devices,
    habits,
    health,
    keys,
    logs,
    me,
    profile,
    public,
    reminders,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    configure_logging()
    yield


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title="feed-the-goose",
        description="The server that owns the chase for Feed the Goose",
        version="0.1.0",
        lifespan=lifespan,
    )

    app.include_router(health.router)

    errors.install(app)
    app.include_router(auth.router)
    app.include_router(me.router)
    app.include_router(keys.router)
    app.include_router(habits.router)
    app.include_router(logs.router)
    app.include_router(chase.router)
    app.include_router(days.router)
    app.include_router(profile.router)
    app.include_router(public.router)
    app.include_router(devices.router)
    app.include_router(reminders.router)

    return app


app = create_app()
