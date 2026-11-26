# Architecture

## Overview

feed-the-goose is a Python API service using FastAPI with a layered architecture.

## Project Structure

```
src/feed_the_goose/
  app.py               # FastAPI app factory
  config.py            # Pydantic-settings config from env vars
  logging.py           # structlog setup
  routers/             # HTTP endpoint definitions
    health.py          # /healthz, /readyz
  controllers/         # Request orchestration
  services/            # Business logic
  dtos/                # Pydantic request/response models
  clients/             # External API/service clients
  db.py                # Async engine/session factory
  models/              # SQLAlchemy async models
  repositories/        # Data access layer
tests/
  unit/                # Fast, isolated unit tests
  integration/         # Tests with real dependencies
  e2e/                 # End-to-end tests
```

## Layering

```
routers (HTTP endpoints, parse requests into DTOs)
  -> controllers (orchestrate across services)
    -> services (business logic, framework-agnostic)
      -> clients (external API calls)
      -> repositories (data access, return SQLAlchemy models)
        -> models (SQLAlchemy)
```

DTOs (Pydantic models) are used at the router and controller level for API I/O. They are always separate from database models.

## Toolchain

| Tool | Purpose |
| ---- | ------- |
| uv | Package management, virtual environments |
| hatchling | Build backend |
| ruff | Formatting and linting |
| ty | Type checking |
| pytest | Testing |
| FastAPI | Async web framework |
| uvicorn | ASGI server |
| structlog | Structured logging |
| pydantic-settings | Configuration |
| SQLAlchemy | Async ORM |
| Alembic | Database migrations |

## Conventions

- All configuration is in `pyproject.toml`.
- Version is the single source of truth in `pyproject.toml`, read via `importlib.metadata`.
- `py.typed` marker enables downstream type checking (PEP 561).
- Health endpoints are always available at `/healthz` and `/readyz`.
