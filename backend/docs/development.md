# Development

## Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/)
- [just](https://just.systems/)
- [Docker](https://www.docker.com/) (for dependencies)

## Setup

```sh
# Install just, uv, Python 3.12 and the locked dependencies
bash ../.agents/setup

# Copy environment file
cp .env.example .env
```

## Database

```sh
# Start Postgres 16 in Docker (in an orb: export DOCKER="sudo docker")
just db-up

# Run migrations
just migrate

# Stop Postgres
just db-down
```

## Running Locally

```sh
just dev
```

The API will be available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

## Common Tasks

```sh
# Format and lint
just fmt-fix
just lint-fix

# Type check
just typecheck

# Run tests
just test-unit
just test-all

# Full pre-push check
just gate

# Full check including integration and e2e
just gate-expensive
```

## Testing

Tests are organized by type:

- `tests/unit/` — fast, isolated tests
- `tests/integration/` — tests with real dependencies
- `tests/e2e/` — end-to-end tests

Use `@pytest.mark.external` for tests that hit external services. These run via `just test-external`.

## Docker

```sh
# Build image
docker build -t feed-the-goose .

# Run container
docker run -p 8000:8000 feed-the-goose
```
