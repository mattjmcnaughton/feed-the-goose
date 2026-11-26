# Feed the Goose

A habit app in which a pursuer chases the user through each day and logging habits keeps the
user ahead. This glossary fixes the words used in code, the API, tests and documents.

## Language

### The chase

**Chase**:
One user's pursuit over one day: the pursuer walks toward the user, and logs move the user
ahead.
_Avoid_: Game, run, round, session

**Pursuer**:
The character that chases the user. The goose is the only pursuer in v1.
_Avoid_: Goose (in rules, API or database), enemy, foe, chaser

**Step**:
The unit of distance in a chase. The pursuer walks 100 steps in a full day.
_Avoid_: Point, score, metre

**Lead**:
How many steps the user is ahead of the pursuer at an instant.
_Avoid_: Gap, distance, score, balance

**Starting lead**:
The lead at the start of a day, before the pursuer walks or the user logs.

**Walked**:
The steps the pursuer has covered so far in a day.

**Earned**:
The steps the user's logs have gained so far in a day.

**Pace**:
The steps the pursuer walks per hour, which the API returns as `steps_per_hour`.
_Avoid_: Speed, rate

### Habits and logs

**Habit**:
Something the user means to do every day, with a unit, a target and a chunk.
_Avoid_: Goal, task, debt, payment

**Target**:
The amount of a habit that finishes it for a day, such as 50 reps.
_Avoid_: Goal, total, quota

**Chunk**:
The usual amount of a habit logged in one tap, such as 10 reps.
_Avoid_: Step (it means distance here), increment, default amount

**Share**:
The steps a habit is worth when finished: 100 divided equally among the day's habits.

**Log**:
A record that the user did some amount of one habit at one instant.
_Avoid_: Entry, payment, check-in, completion

**Undo**:
Withdrawing a log whose day has not settled. The log stays on record as undone.
_Avoid_: Delete, remove, revert

**Source**:
The surface a log came from: the app, a widget, Shortcuts, the API or MCP.

### Days

**Day**:
One user's chase period, named by the local date on which it starts.
_Avoid_: Date (for the period), today (in server code)

**Day window**:
The stretch from a day's start to its end, set by the user's day start, day end and time zone.
_Avoid_: Schedule, active hours

**Night**:
The time between one day's end and the next day's start. The pursuer does not walk at night.

**Settle**:
The moment a day becomes final, which is when the next day starts. A settled day never changes.
_Avoid_: Close, lock, finalize, end

**Running**:
The state of a day that is under way and is neither complete nor caught.

**Complete**:
The state of a day in which every habit reached its target before the pursuer caught the user.
_Avoid_: Fed (outside the goose's words), won, done, finished

**Short**:
The state of a day that reached its end with lead left and at least one habit unfinished.
_Avoid_: Missed, partial, failed

**Caught**:
The state of a day in which the lead reached zero.
_Avoid_: Lost, failed, pecked (outside the goose's words)

**Event**:
What a log or an undo did to the chase: `gain`, `complete`, `caught` or `undone`.

**Gain**:
The event of a log that earned steps without finishing or ending the day.

### Streak

**Streak**:
The count of complete days since the user was last caught. A short day leaves it unchanged.
_Avoid_: Run, chain

**Stage**:
The pursuer's rank from 0 to 4, set by the streak.
_Avoid_: Level, rank, size

### Sharing and access

**Profile**:
The page a user chooses to publish, showing the streak, the current lead and recent days.

**Handle**:
The name in a profile's address, such as `matt` in `/matt`.
_Avoid_: Username, slug

**App session**:
The credential the app, the widgets and the intents use after sign-in.
_Avoid_: Login, token (alone)

**API key**:
A credential the user creates for scripts, which works on the REST API only.

**MCP key**:
A credential the user creates for an MCP client, which works at `/mcp` only.

**Installation**:
One install of the app on one device, which holds that device's push tokens.
_Avoid_: Device (for the record), client

**Reminder**:
A push notification the server sends when the lead is low or the day is about to end.
_Avoid_: Alert, nudge

**Retry queue**:
The logs a device has recorded but the server has not yet confirmed.
_Avoid_: Offline store, outbox, cache

### The goose's words

These belong to the goose and appear only in the app's art and copy, never in the rules, the
API or the database.

**Crust**:
What the user throws the goose on a gain.

**Loaf**:
What the goose gets on a complete day.

**Fed**:
The goose's word for a complete day.

**Snap, Feast, Peck**:
The clips the app plays for a gain, a complete day and a caught day.

**Gosling**:
The goose at stage 0.
