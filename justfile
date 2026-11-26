# Forwards to backend/justfile and clients/ios/justfile.

backend := "just --justfile backend/justfile --working-directory backend"
ios := "just --justfile clients/ios/justfile --working-directory clients/ios"

# List recipes
default:
    @just --list

# Run any backend recipe: just backend <recipe> [args]
backend *args:
    {{ backend }} {{ args }}

# Run any iOS recipe: just ios <recipe> [args]
ios *args:
    {{ ios }} {{ args }}

# Backend: format, lint, types and unit tests
gate:
    {{ backend }} gate

# Backend: the gate plus integration and end-to-end tests (needs Postgres)
gate-expensive:
    {{ backend }} gate-expensive

# Backend: start Postgres in Docker
db-up:
    {{ backend }} db-up

# Backend: stop Postgres
db-down:
    {{ backend }} db-down

# Backend: apply migrations
migrate:
    {{ backend }} migrate

# Backend: serve the API on port 8000
dev:
    {{ backend }} dev

# Backend: run the reminder worker
worker:
    {{ backend }} worker

# Backend: write clients/openapi.json
openapi:
    {{ backend }} openapi

# Backend: check clients/openapi.json is current
openapi-check:
    {{ backend }} openapi-check

# iOS: generate the Xcode project
ios-generate *args:
    {{ ios }} ios-generate {{ args }}

# iOS: build the app
ios-build *args:
    {{ ios }} ios-build {{ args }}

# iOS: run unit and snapshot tests
ios-test *args:
    {{ ios }} ios-test {{ args }}

# iOS: run UI tests
ios-uitest *args:
    {{ ios }} ios-uitest {{ args }}

# iOS: boot the pinned simulator
ios-boot *args:
    {{ ios }} ios-boot {{ args }}

# iOS: install the app on the simulator
ios-install *args:
    {{ ios }} ios-install {{ args }}

# iOS: take a simulator screenshot
ios-screenshot *args:
    {{ ios }} ios-screenshot {{ args }}
