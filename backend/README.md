# feed-the-goose

The server that owns the chase for Feed the Goose

## Getting Started

### Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/)
- [just](https://just.systems/)
- [Docker](https://www.docker.com/) (for dependencies)

### Installation

```sh
bash ../.agents/setup   # just, uv, Python 3.12 and the locked dependencies
cp .env.example .env
```

### Database

```sh
just db-up     # Postgres 16 in Docker; set DOCKER="sudo docker" in an orb
just migrate
```

### Running

```sh
just dev       # http://localhost:8000/healthz and /readyz
```

## Development

```sh
# Check formatting and linting
just fmt
just lint

# Fix formatting and linting
just fmt-fix
just lint-fix

# Run type checker
just typecheck
```

## Testing

```sh
# Run unit tests
just test-unit

# Run all tests
just test-all

# Full pre-push check
just gate
```

## Deployment

```sh
# Build Docker image
docker build -t feed-the-goose .

# Run container
docker run -p 8000:8000 feed-the-goose
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for project structure and design decisions.

## API

See [docs/api.md](docs/api.md) for endpoint reference.

## License

[Proprietary](LICENSE)
