"""FastAPI application factory."""

from contextlib import asynccontextmanager

from fastapi import FastAPI

from feed_the_goose.logging import configure_logging
from feed_the_goose.routers import health


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

    return app


app = create_app()
