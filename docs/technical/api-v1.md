# Feed the Goose API spec (v1)

This is the Amp artifact "Feed the Goose API spec (v1 draft)", revision 6 of 2026-11-26,
copied into the repository so that every ticket can read it. Passages marked **[Amended]**
were added or changed by the [design doc](tdds/01-v1.md), which lists them in §0.3. Once
ticket T02 lands, `clients/openapi.json` is the contract and this file explains it.

The server owns the rules. The iOS app, the widgets, the App Intents, MCP and the public
profile all read the chase from here. The phone keeps a small retry queue so that no log is
lost when the signal drops, but it never works out the chase itself.

Built from the `python-service` template: FastAPI, Postgres, SQLAlchemy and Alembic. FastAPI
publishes this spec as OpenAPI, and `swift-openapi-generator` builds the iOS client from it.

## One chase, many pursuers

The product is a **chase**. The goose is the first **pursuer**; a pirate, a dinosaur or a ghost
can follow. The API and the rules never mention geese or bread:

| In the API | Goose | Pirate (later) |
| --- | --- | --- |
| `pursuer: "goose"` | Feed the Goose | Pay the Pirate |
| A `gain` event | A crust lands (Snap) | A coin is paid |
| A `complete` day | The goose is fed (Feast) | The debt is cleared |
| A `caught` day | The goose pecks you (Peck) | The pirate boards you |
| `streak.stage` 0 to 4 | Gosling up to full-grown goose | A bigger ship |

- Each user has one `pursuer`. The server stores it, checks it against the list it supports,
  and returns it, but it doesn't change the rules.
- The app owns the art, animations and words for each pursuer and maps each event to the right
  clip.
- If a later pursuer needs different rules, give the chase a `ruleset` version then. v1 has
  one.

## Conventions

- Base path `/v1`. JSON in and out.
- Auth: `Authorization: Bearer <token>`, except for the auth endpoints and the public profile.
  See **Credentials**.
- Timestamps are ISO 8601 in UTC, such as `2026-11-26T14:05:00Z`. A **day** is named by the
  local date on which it starts, such as `2026-11-26`.
- Steps are numbers with one decimal place. The app rounds them for display.
- The client creates each log's ID as a UUIDv7. Sending the same ID again is safe, and this is
  what makes the retry queue work.
- **[Amended]** Every other ID is a UUID that the server creates, sent as a string. IDs such as
  `h_01` in the examples below are placeholders.
- Errors use `application/problem+json`, with a `type` the app can switch on:

| Status | `type` | When |
| --- | --- | --- |
| 401 | `unauthenticated` | Missing, expired or revoked credential, or the wrong kind of credential for this route |
| 403 | `identity_not_admitted` | **[Amended: listed here]** A verified email that is not on the allowlist |
| 404 | `not_found` | Unknown habit, log, key or handle |
| 404 | `no_chase` | **[Amended]** The user has no habit for the current day |
| 409 | `day_settled` | A log or undo for a day that is already settled |
| 409 | `handle_taken` | Someone else has that handle |
| 422 | `invalid` | Validation failed; `errors` lists the fields |
| 429 | `rate_limited` | Includes `Retry-After`. **[Amended]** Reserved: the v1 build does not rate-limit yet. |
| 501 | `not_implemented` | **[Amended]** A route whose ticket has not landed. It must not exist at release. |

## Each user's day

Each user sets their day, and it's stored on the user:

| Setting | Example | Allowed |
| --- | --- | --- |
| `time_zone` | `America/New_York` | Any IANA zone |
| `day_start` | `06:00` | A local time |
| `day_end` | `00:00` | A local time; it can be after midnight, such as `02:00` for a night owl |

- The day must be between 8 and 22 hours long. The night between `day_end` and the next
  `day_start` can't be empty.
- **A change takes effect from the next day's start.** A day already under way keeps its
  window, so changing the time zone or the hours can't stretch or shrink it.
- The app sets `time_zone` from the phone at sign-up. Later, when the phone's zone changes, the
  app asks before changing it, because a trip shouldn't move your day without you knowing.
- **[Amended]** New users get `day_start` `06:00` and `day_end` `00:00`.

## The rules the server applies

These follow the README's "Outrun" rule. Every number is a server setting, not a constant in
the app. **[Amended]** The design doc §5.3 states them exactly, with a table of example days.

- The pursuer walks 100 steps between `day_start` and `day_end`, at an even pace. An 18-hour
  day is 100 / 18 ≈ 5.6 steps an hour. The pursuer doesn't walk during the night.
- Each habit is worth an equal share of 100 steps. A log earns `share × amount / target`,
  capped at whatever is left of that habit for the day.
- `lead = starting_lead + earned − walked`.
- Starting lead: 100 after a complete day; after a short day, the lead left when it settled;
  after a caught day, 100.
- **Complete:** every habit is done. The day locks as won.
- **Caught:** the lead reaches 0. The day locks.
- **Short:** `day_end` comes with some lead left and not every habit done.
- **Habit edits take effect from the next day.** Today's shares never change mid-day.
- **[Amended] The first day.** A user's first day starts when their first habit is created, if
  that is after `day_start`. The pace is unchanged.
- **Queued logs.** A log counts at its `logged_at`, not when it arrives. The server accepts it
  if:
  - `logged_at` is no later than the time it arrives, plus 2 minutes for clock skew;
  - its day hasn't settled. **A day settles when the next day starts.** Until then the server
    recomputes the day from every log it holds, so a log made at 8 pm that only arrives at
    11 pm can still prevent a catch at 9 pm. A log made during the night counts toward the day
    that just ended.

## Credentials

There are three kinds of credential, and each works only where it belongs. This follows
Slate's TDD 01 and Accanto's TDD 03.

| Kind | Who uses it | Works at | Lifetime |
| --- | --- | --- | --- |
| App session | The iOS app, the widgets and the intents | `/v1/*` | 90 days, extended each time it's used; revocable |
| API key | Scripts, curl, your own tools | `/v1/*` except the key, session and account-deletion routes | Until it's revoked |
| MCP key | Claude Code, Codex, Amp | `/mcp` only | Until it's revoked |

- **The app signs in with Auth0**, in an in-app browser sheet (`ASWebAuthenticationSession`
  through AppAuth-iOS, with PKCE and an ephemeral session).
  - Auth0 offers email and password or a one-time code, and Sign in with Apple as an Auth0
    connection.
  - Apple's guideline 4.8 requires Sign in with Apple only if a social login such as Google is
    offered.
  - **[Amended]** The Auth0 sheet waits for a tenant. Until then the app uses the dev sign-in:
    `POST /dev/token` issues an identity token that `POST /v1/auth/session` accepts in
    development and tests only.
- **The app swaps the identity token for its own session.** It sends the token to
  `POST /v1/auth/session`. The server checks it against the issuer's keys (issuer, audience
  `https://feed-the-goose.mattjmcnaughton.com/v1`, expiry), creates the account on first
  sign-in, and returns an opaque session token. Only the token's SHA-256 hash is stored.
  - This avoids a race. Auth0's refresh tokens rotate on every use and treat reuse as theft,
    and the app, the widget and the intents run as separate processes that would race to
    refresh. A long-lived server session has nothing to refresh, and deleting its row revokes
    it.
- **Only allowlisted emails can sign up.** `ALLOWED_EMAILS` starts with just Matt. A verified
  email that isn't on the list gets a 403 `identity_not_admitted`.
- **API keys work like Accanto's.** You create one in Settings with a name. It has full API
  access as you, except that it can't manage keys or sessions or delete the account.
- **Keys** are `ftg_` followed by 32 random bytes, encoded URL-safe. A key is shown once; the
  server stores only its SHA-256 digest and checks it again on every request, so revoking a key
  stops it on its next call.
- `/mcp` refuses app sessions and API keys, and `/v1` refuses MCP keys. An MCP client therefore
  can't go around the MCP tools.
- **An MCP key can't edit or delete habits, change settings or touch keys.**
- **Hosted OAuth comes later.**

## Objects

### Chase

The state of the current day's chase. Every write returns it, so the app never needs a second
call.

```json
{
  "date": "2026-11-26",
  "pursuer": "goose",
  "state": "running",
  "as_of": "2026-11-26T23:00:00Z",
  "lead": 80.0,
  "starting_lead": 100.0,
  "earned": 46.7,
  "walked": 66.7,
  "steps_per_hour": 5.56,
  "day_starts_at": "2026-11-26T11:00:00Z",
  "day_ends_at": "2026-11-27T05:00:00Z",
  "next_day_starts_at": "2026-11-27T11:00:00Z",
  "caught_at": null,
  "habits": [
    { "habit_id": "h_01", "name": "Pushups", "unit": "reps", "target": 50, "chunk": 10, "logged": 20, "steps": 13.3, "done": false },
    { "habit_id": "h_02", "name": "Workout", "unit": "minutes", "target": 30, "chunk": 10, "logged": 30, "steps": 33.3, "done": true },
    { "habit_id": "h_03", "name": "Reading", "unit": "pages", "target": 20, "chunk": 5, "logged": 0, "steps": 0.0, "done": false }
  ],
  "streak": { "complete_days": 13, "stage": 2 }
}
```

- `state` is one of `running`, `complete`, `short` or `caught`.
- `lead` is exact at `as_of`. While `state` is `running`, a client works out the current lead
  as `lead − steps_per_hour × hours since as_of`, and stops at `day_ends_at`. That's
  arithmetic, not the rules.
- `caught_at` is when the lead reaches 0 if nothing more is logged. It's `null` when that
  wouldn't happen by `day_ends_at`. After a catch it is when the catch happened.
- **[Amended]** `next_day_starts_at` is when this day settles and the next begins. Clients
  refresh then.
- **[Amended]** Each habit carries its `chunk`, so a widget can draw its button from the Chase
  alone. `habits` are in `position` order.
- **[Amended]** `streak.complete_days` includes today when today is complete. `stage` is 0, 1,
  2, 3 or 4 for streaks from 0, 3, 7, 14 and 30.

### Event

Returned alongside the Chase after a log or an undo, so the app knows which clip to play for
the user's pursuer.

```json
{ "kind": "gain", "habit_id": "h_01", "steps": 6.7 }
```

`kind` is one of `gain`, `complete`, `caught` or `undone`. **[Amended]**

- `complete`: this log is the one that finished the last habit.
- `caught`: the log was made at or after the catch, so it earned nothing.
- `gain`: any other log. `steps` is what it earned, which may be 0.
- `undone`: the result of an undo. `steps` is what the log had earned.

### Log

**[Amended: the draft did not define it.]**

```json
{
  "id": "0193a5b8-7c1e-7a3b-9f42-5d6e7f809a1b",
  "habit_id": "h_01",
  "amount": 10,
  "logged_at": "2026-11-26T14:05:00Z",
  "source": "app",
  "date": "2026-11-26",
  "steps": 6.7,
  "undone_at": null
}
```

### Habit

```json
{
  "id": "h_01",
  "name": "Pushups",
  "unit": "reps",
  "target": 50,
  "chunk": 10,
  "position": 0,
  "effective_from": "2026-11-20",
  "archived_from": null
}
```

`chunk` is the usual amount. The Feed widget's "+10" button logs one chunk.

## Endpoints

### Auth

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/v1/auth/session` | `auth0_access_token`, `time_zone`, `device_name` | `session_token`, `expires_at`, `user`. The account is created on first sign-in. `time_zone` is used only then. |
| GET | `/v1/auth/sessions` |  | `[{ id, device_name, created_at, last_used_at, current }]` |
| DELETE | `/v1/auth/sessions/{id}` |  | 204. Pass `current` as the ID to sign out. |

### Me

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/v1/me` |  | `id`, `email`, `display_name`, `pursuer`, `time_zone`, `day_start`, `day_end`, `pending` (changes waiting for the next day, with `effective_from`), `created_at` |
| PATCH | `/v1/me` | `display_name?`, `pursuer?`, `time_zone?`, `day_start?`, `day_end?` | The updated user. Changes to the day take effect from the next day. A change of `pursuer` takes effect now; streaks and habits don't depend on the pursuer, so nothing else changes. |
| DELETE | `/v1/me` |  | 204. Deletes the account and all of its data and revokes every session and key. The App Store requires this. **[Amended]** Deleting the Auth0 user waits for the tenant. |

### Keys

App session only.

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/v1/me/keys` |  | `[{ id, kind, name, created_at, last_used_at }]` |
| POST | `/v1/me/keys` | `kind` (`api` or `mcp`), `name` | The key, including `secret`, which is returned this once only |
| DELETE | `/v1/me/keys/{id}` |  | 204 |

The app's Settings screen shows the MCP URL and a copyable `claude mcp add` command.

### Habits

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/v1/habits` |  | Active and upcoming habits |
| POST | `/v1/habits` | `name`, `unit`, `target`, `chunk` | The Habit, with `effective_from` set to the next day, or to the current day if no log has been made yet in it |
| PATCH | `/v1/habits/{id}` | Any of `name`, `unit`, `target`, `chunk`, `position` | The Habit. A change to `target` takes effect from the next day; renames, a new chunk and reordering take effect now. |
| DELETE | `/v1/habits/{id}` |  | The Habit, with `archived_from` set to the next day |

The number of habits is capped at 8. A ninth is refused with 422 `invalid`.

### Logs

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/v1/logs` | `id`, `habit_id`, `amount?`, `logged_at`, `source` | 201 with `log`, `event`, `chase`. 200 with the same shape if this `id` already exists. |
| DELETE | `/v1/logs/{id}` |  | `log`, `event` (`undone`) and `chase` |
| GET | `/v1/logs?date=2026-11-26` |  | That day's logs, newest first, including undone ones |

- `amount` defaults to the habit's `chunk`.
- `source` is one of `app`, `widget`, `shortcuts`, `api` or `mcp`, and is kept for stats.
- `logged_at` is set on the device. When the phone retries a queued log it sends the original
  value, never the time of the retry.
- Undo works for any log whose day hasn't settled. Undoing a log can also undo a `complete`
  result.
- A log for a day already `complete` or `caught` is stored but earns nothing.
- **[Amended]** An undone log stays undone. Sending its `id` again returns it with `undone_at`
  set.

### Chase and history

| Method | Path | Returns |
| --- | --- | --- |
| GET | `/v1/chase/today` | The Chase for the current day; during the night, the day that just ended. 404 `no_chase` when the user has no habit for it. |
| GET | `/v1/days?from=2026-11-01&to=2026-11-26` | `[{ date, pursuer, result, end_lead, complete_days }]`, where `result` is `complete`, `short`, `caught` or `running` |

### Public profile

| Method | Path | Auth | Returns |
| --- | --- | --- | --- |
| GET | `/v1/me/profile` | App session | `handle`, `public` |
| PUT | `/v1/me/profile` | App session | Sets `handle` (3 to 30 characters: a to z, 0 to 9 and `-`) and `public` |
| GET | `/v1/profiles/{handle}` | None | `display_name`, `pursuer`, `complete_days`, `stage`, `state`, `lead`, `as_of`, `steps_per_hour`, `day_ends_at` and the last 35 `days` as `[{ date, result }]` |
| GET | `/{handle}` | None | The same as a server-rendered HTML page, drawn with that user's pursuer |

The public endpoints never include habit names, amounts, log times or the user's day hours.
Both return 404 when the profile isn't public. **[Amended]** Handles that would shadow a route,
such as `v1` and `mcp`, are refused with 422 `invalid`.

### MCP

- FastMCP, serving Streamable HTTP at `/mcp` with no session state.
- It's mounted as middleware ahead of routing.
- It accepts MCP keys only.

| Tool | Kind | Input | Same as |
| --- | --- | --- | --- |
| `get_chase` | read |  | `GET /v1/chase/today` |
| `list_habits` | read |  | `GET /v1/habits` |
| `get_history` | read | `days?` (default 30) | `GET /v1/days` |
| `log_habit` | write | `habit_id`, `amount?`, `idempotency_key` | `POST /v1/logs` with `source: mcp`. The server sets `logged_at` to now. |
| `undo_log` | write | `log_id` | `DELETE /v1/logs/{id}` |

- **One tool catalog.** `services/tools.py` holds the tools for MCP and for a future in-app
  assistant. Both call the same services as REST, so the rules run only once.
- **Habit names are wrapped** as `{"untrusted": "..."}` in results.
- **Error messages are fixed text.** They never echo the input or the exception.
- `log_habit` and `undo_log` run immediately; there's no suggest mode, because a log is cheap
  to undo.
- Excluded: anything that edits or deletes habits, keys, settings or the account.

### Devices and push

The server sends every notification through APNs, so a log from any source moves the
reminders.

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| PUT | `/v1/me/devices/{installation_id}` | `apns_token`, `widget_push_token?`, `environment` (`sandbox` or `production`), `app_version` | 204. Registers or refreshes this install's tokens. |
| DELETE | `/v1/me/devices/{installation_id}` |  | 204. Called on sign-out. |
| GET | `/v1/me/reminders` |  | `{ enabled, when_lead_below, quiet_hours }` |
| PUT | `/v1/me/reminders` | Same fields | The updated preferences |

- **[Amended]** `quiet_hours` is `{ "start": "22:00", "end": "07:00" }` in the user's time
  zone, or `null`. `enabled` defaults to false and `when_lead_below` to 30.
- **Reminders:**
  - one when the lead drops below `when_lead_below`;
  - one an hour before `caught_at`;
  - one at `day_ends_at` minus an hour if the day is unfinished.

  Each day gets at most three, none in quiet hours. A worker keeps the due reminders in a
  table and recomputes them whenever the Chase changes.

- **Widget refresh:** after a log from any source, the server sends a widget push using iOS 26
  WidgetKit push updates, so the status widget redraws without the app running.
  **[Amended]** Not built until there is an Apple push key and a phone to check it on.
- APNs uses a token-signing `.p8` key, stored as a secret.
- An `apns_token` is deleted when APNs answers `410 Unregistered`.

### Health

`/healthz` and `/readyz`, from the template. `/readyz` checks that the database answers.

### Development only

**[Amended]** `/dev/token`, `/dev/seed` and `/dev/pushes` exist only when `ENV` is
`development` or `test`. They are not in `clients/openapi.json`. See the design doc §5.10.

## The iOS retry queue

1. The app adds the log to a queue in the App Group, giving it an `id` and a `logged_at`.
2. It sends `POST /v1/logs` with a 5-second timeout.
3. When the request succeeds: it plays the clip for the `event` and the user's pursuer, saves
   the Chase for the widgets, reloads both widgets, and removes the log from the queue.
   Reminders move on the server.
4. When the request fails: the widget or the action says "10 pushups logged, they'll count when
   you're back online". The log stays in the queue, and the app retries it when it opens, when
   the network comes back, and from a background task.
5. A 409 `day_settled` drops the log from the queue and tells the user it was too late.

## Open questions

1. Is the streak option "Grows", shown as `streak.stage`? *The build assumes yes.*
2. Is 8 the right cap on habits, and are 8 to 22 hours the right limits for a day? *The build
   assumes yes.*
3. If you undo a log on a complete day, does the public streak change right away, or only once
   the day settles? *The build assumes right away.*
