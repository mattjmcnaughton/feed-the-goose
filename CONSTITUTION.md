# Feed the Goose Constitution

Drafted 2026-11-26 at Matt's request, before the v1 build.

These are the durable commitments for Feed the Goose and for the agents who build it. They are
obligations, not a claim that any code satisfies them: on the day this was written the
repository held no app code.

Each principle names its source. **Decided** means Matt said it. **Proposed** means it follows
a recommendation Matt has not yet answered; it governs the build until he amends it. The open
recommendations are listed at the top of the [design doc](docs/technical/tdds/01-v1.md).

## Part 1: the product

### 1. The server owns the rules

*Decided ("Yes server only with a queue").*

Only the server works out a chase: what a log earns, how far the pursuer has walked, and
whether a day is running, complete, short or caught. Every client reads that result: the app,
the widgets, the App Intents, MCP, the API and the public profile.

A client may do display arithmetic the server has licensed: it may subtract
`steps_per_hour × elapsed time` from a lead the server sent, and stop at the times the server
sent. A client never decides that a day is complete or caught, never computes what a log is
worth, and never stores a rule number as a constant. Every rule number is a server setting.

Client-side checks and disabled buttons are for usability. They do not enforce anything.

### 2. The core is pursuer-neutral

*Decided ("Streaks and goals are agnostic of pursuer").*

The product is a chase, and the goose is its first pursuer. The rules, the database, the API
and the MCP tools never mention geese, bread, crusts or loaves. They speak of a pursuer, a
lead, steps, and `gain`, `complete`, `short` and `caught`. The app owns the art, the clips and
the words for each pursuer and maps events onto them.

A change that puts a goose word into `backend/` or into `clients/openapi.json` breaks this
principle. The only exceptions are the product's own name and the value `"goose"` in the list
of supported pursuers. A later pursuer
that needs different rules gets a ruleset version, not a fork of the rules.

### 3. A log is never lost and never counted twice

*Decided (the retry queue); the wording follows Aleph's constitution §3.*

The client creates each log's ID and its `logged_at` once, at the moment the user acts, and
sends the same values on every retry. The server treats a repeated ID as the same log. A log
counts at its `logged_at`, not at the time it arrives.

An undone log stays undone: a late retry of its ID must not bring it back. Related writes that
make up one operation succeed or fail together. These guarantees cross processes, so they rest
on database constraints and transactions, not on an in-process lock.

### 4. Days are explicit, and a settled day is history

*Decided (each user sets day start, day end and time zone); the settle rule is proposed.*

A day is a window the user chose, in a time zone the user chose. A change to the window, the
time zone, a habit's target, or the set of habits takes effect from the next day, so a day
under way never stretches, shrinks or changes its shares. The app asks before it changes the
time zone.

Until a day settles, the server recomputes it from every log it holds. Once it settles it is
never rewritten: no log, undo or setting can change it.

Rule code receives the time as an input. It reads no clock, no database and no configuration,
so every rule can be tested with a table of example days.

### 5. Private by default; the profile is a published projection

*Decided (public profile in v1); the bounds follow Aleph's constitution §1.*

Every operation on a user's data checks the authenticated account. Knowing an ID is not
authorization.

One exception: anyone may read the profile a user chose to publish, for as long as it stays
published. That read is GET-only, re-checks publication on every request, reads and sets no
session or cookie, and returns only fields named for publication. Habit names, units, amounts,
log times and the user's day hours are never among them. The server builds the profile from an
explicit list of fields, and a test fails when a field outside that list appears.

### 6. Each credential works only where it belongs

*Decided (API keys like Accanto's, MCP keys like Slate's).*

There are three kinds of credential: an app session, an API key and an MCP key. `/v1` refuses
MCP keys, and `/mcp` refuses sessions and API keys, so an MCP client cannot go around the MCP
tools. A secret is shown once, and only its SHA-256 digest is stored. The server checks the
digest on every request, so revoking a credential stops it on its next call.

Text that came from a user or a model is untrusted input. MCP results wrap habit names as
untrusted, and MCP error messages are fixed text that never echo the input or an exception.
Nothing a model says grants access or authorizes a change.

### 7. One contract, generated clients

*Proposed (decision A2).*

`clients/openapi.json`, exported from the server, is the contract, and it is committed. The
Swift client is generated from it. Shared fixtures in `clients/fixtures/` are checked by both
the Python tests and the Swift tests. A contract change lands with the regenerated file, the
fixtures and both sides in step, or names the tracked work that will close the gap. The
database schema is not the contract: API types are separate from persistence models.

### 8. Failure, absence and success are different states

*Proposed; follows Aleph's constitution §4.*

A log waiting in the retry queue is not logged, and the app says so ("they'll count when
you're back online"). A lead the client could not refresh is shown as stale, not as current. A
network failure never appears as a zero lead, an empty habit list or a caught day. A success
response means the promised operation happened.

### 9. Logging takes one tap, and partial logs count

*Decided ("Must be very easy"; "Any part of a habit can be logged").*

A user can log a habit's usual chunk without opening the app, from a widget button or a
Shortcuts action. A feature that makes logging slower, or that requires the app to be open
first, needs Matt's agreement.

### 10. Complexity is earned, and dependencies are approved

*Proposed (decisions D4 and F4).*

Use the stack and the boundaries in the design doc unless a concrete requirement justifies a
change. The app is plain SwiftUI with Observable view models: no Composable Architecture and
no dependency-injection framework. Effects such as the API client, the clock and the queue are
passed in explicitly, behind a protocol only where a test needs a fake.

A dependency outside the approved list in the design doc stops for Matt's approval. An
abstraction, layer or service is added for a problem that exists, not for one that might.

## Part 2: how the work is done

### 11. Proof before done

*Decided ("They can report back when they have proof that their feature is working"); the
evidence levels follow decision E2.*

Work is done when an executed check shows the behavior, not when the code is written. A report
shows the command and its decisive output. UI work also shows the simulator screenshots or the
recording that the agent inspected.

Evidence has levels, and a report names the level it reached:

1. **Tests** show the behavior they exercise. Database guarantees need a test against real
   Postgres. Rules need the example table.
2. **Simulator evidence** shows the app running. It is evidence, not acceptance.
3. **Acceptance** is Matt's check on a real phone. Widget buttons, the Lock Screen, push
   delivery and offline behavior on a device are not accepted until then.

Never weaken, skip or special-case a check to make it pass. Never describe unverified behavior
as working; say what was not checked. No test calls a model provider or a real Apple, Auth0 or
Neon service.

### 12. Commits follow Conventional Commits

*Decided.*

Every commit message is `<type>(<scope>): <subject>`, with an optional body that explains why.

- **Type:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
  or `revert`.
- **Scope:** the area changed, such as `rules`, `api`, `mcp`, `ios`, `widgets` or `docs`. Leave
  it out when the change is broad.
- **Subject:** imperative, lower case, no final period, at most 72 characters.
- One commit holds one logical change. No emoji and no AI attribution or co-author trailers.

The `create-commit` skill writes messages in this form.

### 13. Changes land through the feature branch, and some actions wait for Matt

*Decided (merging into `v1-build` overnight needs no further approval; "Don't stress about
deployment yet"); the list of actions that wait follows decision F3.*

Each ticket is built on its own branch and merged into the feature branch named in the work
breakdown. For the v1 build that branch is `v1-build`, and merging into it needs no further
approval once the ticket's proof exists and its checks pass.

These always wait for Matt, whatever a ticket says:

- merging or pushing to `main`;
- deploying, running `amp boxes deploy`, or uploading to TestFlight or App Store Connect;
- creating or changing anything in Auth0, Neon, Apple Developer or production;
- adding a dependency outside the approved list;
- changing the meaning of a principle in this document.

A secret is never committed, logged or written into a fixture. Fixtures and seeds use
synthetic data.

### 14. One owner per file, and stop rather than guess

*Proposed.*

A ticket names the files it owns. An agent changes files outside its ticket only for the
shared files the work breakdown lists, and says so in its report. When a ticket needs a
contract or schema change that another ticket depends on, the change lands first, on its own,
and the others pick it up.

When a decision is missing and a wrong guess would be expensive to undo, an agent finishes
what does not depend on it and reports the question. For a small gap it picks the simplest
option that satisfies these principles, records it in the ticket's report, and carries on.

### 15. Use the shared vocabulary and Matt's skills

*Proposed (decision A3); the skills were named by Matt.*

[docs/CONTEXT.md](docs/CONTEXT.md) owns the vocabulary. Use its terms in code, API fields,
tests, documents and reports, and resolve an ambiguous term there instead of adding a synonym.

Agents use Matt's skills for the work they cover: `ship-ticket` for one ticket end to end
(`prep`, `build`, `review-suite`, `resolve-review`, `prove`, `create-commit`), `run-wave` and
`run-waves` to coordinate parallel tickets, `ship-gate` before a merge, `create-pr` and
`merge-pr` for delivery, and `give-update` for progress. The work breakdown records the run's
standing choices so that an unattended run does not stop at a skill's confirmation prompt.

## Governance

Read this document before planning, building or reviewing. A plan names the principles that
apply and the evidence that will check them. A review reports conflicts with them; it does not
claim compliance from prose.

Changing what a principle means needs Matt's explicit agreement and a dated line in the
amendment record. A clarification that keeps the meaning needs neither. Code that violates a
principle is a discrepancy to fix or to raise, never a reason to weaken the principle.

### Document ownership

- This constitution owns the enduring commitments.
- [docs/CONTEXT.md](docs/CONTEXT.md) owns the vocabulary.
- The [v1 PRD](docs/product/prds/01-v1.md) owns scope, scenarios and acceptance criteria.
- The [v1 design doc](docs/technical/tdds/01-v1.md) owns architecture, rule numbers, the
  approved dependency list and the open defaults.
- The [v1 work breakdown](docs/technical/tickets/01-v1.md) owns tickets, file ownership, proof
  and the run's permissions.
- The [README](README.md) owns the introduction and what is built versus intended.
- [AGENTS.md](AGENTS.md) owns commands and working conventions.

When two documents disagree, raise it; do not silently rewrite the other document.

### Amendment record

- 2026-11-26: First draft, written for the v1 build. Principles 1, 2, 3, 5, 6, 9, 11, 12 and 13
  rest on decisions Matt made in the build thread, as does the day window in principle 4.
  Principles 7, 8, 10, 14 and 15, the settle rule in principle 4, and the borrowed bounds in
  principles 5, 11 and 13 are proposed and await his confirmation.
