# Backend guidance

The FastAPI service that owns the chase. Generated from the `python-service` template in
`mattjmcnaughton/templates`. Read the root [AGENTS.md](../AGENTS.md) and the
[constitution](../CONSTITUTION.md) first; the design is in
[TDD 01](../docs/technical/tdds/01-v1.md) §5.

Python 3.12 (`.python-version`), `uv`, `just`, `ruff`, `ty`, `pytest`. Run recipes from here or
from the repository root, which forwards them.

## Commands

| Command | Purpose |
| --- | --- |
| `bash ../.agents/setup` | Install `just`, `uv`, Python and the locked dependencies. Safe to rerun. |
| `just gate` | Format check, lint, types, unit tests. Run before every commit. |
| `just gate-expensive` | The gate plus integration and end-to-end tests. Needs Postgres. The merge gate. |
| `just test-unit` / `test-integration` / `test-e2e` | One test layer. |
| `just fmt-fix` / `lint-fix` | Fix formatting and lint. |
| `just db-up` / `db-down` | Start or stop Postgres 16 in Docker (container `feed-the-goose-postgres`, port 5432). |
| `just migrate` | `alembic upgrade head`. |
| `just dev` | Serve on port 8000 with `ENV=development` and the dev sign-in and `/dev` routes on. |
| `just worker` | The reminder worker (`python -m feed_the_goose.worker`, added by T09). |
| `just openapi` / `openapi-check` | Write or check `clients/openapi.json` (added by T02). |

### In an orb

No Docker daemon runs by default, and the CLI needs `sudo`:

```sh
amp orb service start dockerd --command 'sudo dockerd'
export DOCKER="sudo docker"
just db-up && just migrate
amp orb service start web --command 'cd backend && just dev' --port 8000
curl -i localhost:8000/readyz
```

Start long-lived processes with `amp orb service start`, never with `&` or `nohup`.

## Settings

`config.py` reads the environment (and `.env`; see `.env.example`). `ENV` is `development`,
`test` or `production`. `DATABASE_URL` uses `postgresql+asyncpg://`. `ALLOWED_EMAILS` is a
comma-separated list. Every rule number (TDD §5.3) is a setting here; rule code takes the
values as inputs and never imports `config`.

## Layering

Routers → controllers → services → repositories, with DTOs separate from database models
(TDD §5.1).

- `routers/` parse HTTP and translate responses. No rules, no queries.
- `controllers/` map DTOs to service calls and back.
- `services/` own use cases, authorization, transactions and calls into the domain.
- `domain/` is pure: explicit inputs, returned results, no I/O. It imports no other
  application package, SQLAlchemy, FastAPI or `config`, and reads no clock.
- `repositories/` own queries. `models/` are SQLAlchemy models; `dtos/` are the API contract.
- `clock.py` defines `Clock`. Services receive one; tests pass `FixedClock`.
- `wiring.py` is the one place that builds services from settings.
- `identity/`, `mcp/`, `push/` and `dev/` hold the verifiers, the MCP server, reminders and the
  development-only routes.

No goose words in this directory except the product's name, the package name and the
`"goose"` pursuer value (constitution §2). Check with `rg -i 'goose|bread' src`.

## Tests

- `tests/unit/`: no database, no network.
- `tests/integration/`: real Postgres at `DATABASE_URL`.
- `tests/e2e/`: the app served by uvicorn, over HTTP.
- Async tests use `@pytest.mark.anyio` (asyncio only; see `tests/conftest.py`).
- Expected values come from the spec or by hand, never from the code under test. No test calls
  Apple, Auth0, Neon or a model provider.
- Approved dependencies are in TDD §9. Ask before adding anything else.
