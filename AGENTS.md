# Repository guidance

Read [the constitution](CONSTITUTION.md) before planning, building or reviewing. It holds the
project's commitments, not a claim about what is built. The [README](README.md) says what
exists today.

- Vocabulary: [docs/CONTEXT.md](docs/CONTEXT.md). Use its terms; do not add synonyms.
- Scope and acceptance criteria: [docs/product/prds/01-v1.md](docs/product/prds/01-v1.md).
- Architecture, rule numbers and approved dependencies:
  [docs/technical/tdds/01-v1.md](docs/technical/tdds/01-v1.md).
- Tickets, file ownership, proof and run permissions:
  [docs/technical/tickets/01-v1.md](docs/technical/tickets/01-v1.md).

## Working rules

- Commits follow Conventional Commits (constitution §12). Use the `create-commit` skill.
- Build each ticket on its own branch and merge it into `v1-build`. Never push to `main`,
  deploy, upload to TestFlight, or touch Auth0, Neon, Apple Developer or production
  (constitution §13).
- Ask before adding a dependency that is not in the design doc's approved list.
- A ticket is done when its "Proof" section has been run and the evidence inspected
  (constitution §11).
- Rules live in `backend/src/feed_the_goose/domain/` and take the time as an input. No goose
  words in `backend/` or `clients/openapi.json` (constitution §2).

## Layout

| Path | Contents |
| --- | --- |
| `backend/` | The FastAPI service, generated from the `python-service` template. Added by ticket T01. |
| `clients/openapi.json` | The committed API contract. Added by ticket T02. |
| `clients/fixtures/` | Request and response fixtures checked by Python and Swift tests. Added by ticket T02. |
| `clients/ios/` | The SwiftUI app, widgets and App Intents. Added by ticket T11. |
| `spikes/swiftui-goose/` | The throwaway animation spike, kept as the reference for ticket T12. |
| `docs/prototypes/` | The clickable prototypes that settled the design. |

`backend/` and `clients/ios/` each get their own `AGENTS.md` with commands when they are
created. iOS builds, tests and simulator captures run on a Mac satellite started with the
`macos-26` image; Linux checks are not build or render evidence for the app.
