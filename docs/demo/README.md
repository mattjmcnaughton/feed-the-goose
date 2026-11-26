# The v1 demo

[`v1-demo.mp4`](v1-demo.mp4) is one recording, 8:24 and 11 MB, of the real app in the iOS
Simulator (iPhone 17 Pro, iOS 26.2) talking to the real backend running in an orb. Nothing is
a fixture: each scene seeds its account with `POST /dev/seed` and the server works out every
lead, streak and result. It was recorded on 2026-11-26. How to record it again:
[`docs/technical/demo.md`](../technical/demo.md).

A title card names each scene before it plays. Scenes 7 and 9 play at 2× because they wait
for the pursuer and the worker.

## The scenes

| Starts at | # | Scene | What it shows | PRD |
| --- | --- | --- | --- | --- |
| 0:00 | 1 | Sign in and set up | Dev sign-in as a new account (`new@example.com`), which lands on habit setup. Pushups 50 by 10, Workout 30 by 10 and Reading 20 by 5 are added; each is saved by the server. Done opens Today: 100 steps behind you, no streak yet. | S1, S2 |
| 1:07 | 2 | Log and undo | The seeded `demo` account: 80 steps, a 13-day streak, Big goose. "+10" on Pushups plays Snap: 87 steps, "you gain 7 steps". Undo takes it back to 80. "+10" again. | S3, S4 |
| 1:45 | 3 | Widgets | The Chase and Feed widgets are added to the Home Screen, both at 86 steps. "+5 reading" on the Feed widget logs with the app closed, and both widgets redraw at 95. | S8 |
| 3:18 | 4 | MCP | An MCP key, "Claude Code", made in Settings, which shows the MCP URL and the `claude mcp add` command. From the orb, `log_habit` at `/mcp` logs 5 pages of Reading. The app, brought forward, shows Reading at 10 of 20 and 103 steps. | S13 |
| 4:22 | 5 | Fed | Finish on Pushups, then on Reading. The last plays Feast: "The goose is fed", the streak goes from 13 to 14 days and the goose grows to Boss goose. | S5, S11 |
| 4:54 | 6 | Public profile | `localhost:8000/matt` in a browser on the orb: "Fed the goose 14 days running", the last 35 days (32 fed, 2 short, 1 caught), and no habit names. | S12 |
| 5:06 | 7 | Caught | A seeded `caught-soon` account: "The goose is right behind you", then about a minute after seeding "The goose got you" and Peck. The log buttons are disabled. | S6 |
| 5:48 | 8 | Offline | A seeded `almost-complete` account. The orb stops the web service; Finish 10 on Pushups is queued under "Waiting to send … at 2:41 PM". The service comes back, a pull refreshes, "Your waiting log went through" and Pushups is done. | S10 |
| 7:12 | 9 | Reminder | Reminders turned on in Settings. The worker plans "You'll be caught in 30 seconds" and the recording sender captures it; its payload from `GET /dev/pushes` is delivered with `xcrun simctl push`, **not APNs**, and shows as a banner. | S14 |

### Evidence

- Scene 4, the MCP requests and the `log_habit` response with `source: mcp` and `steps: 8.3`:
  [`evidence/scene-4-mcp.txt`](evidence/scene-4-mcp.txt).
- Scene 8, the stored log beside the times the web service stopped and came back:
  [`evidence/scene-8-offline.txt`](evidence/scene-8-offline.txt). The log was made at
  19:41:32Z, while the server was down from 19:41:28Z to 19:41:57Z, and it is stored with
  `logged_at` 19:41:32Z: the time it was made, not the time it was delivered.

### A second run

A second run from [`docs/technical/demo.md`](../technical/demo.md), on an erased simulator,
reached the same nine scenes with every `DemoTests` scene passing: scenes 1 to 7 on 2026-11-26,
then 8 and 9 on 2026-11-27 on a new satellite after setup again. In its scene 8 the log was
made at 13:51:14Z, while the web service was down from 13:51:13Z to 13:51:42Z, and was stored
with `logged_at` 13:51:14Z.

## The gallery

Screenshots from the same run, in [`gallery/`](gallery), at half size.

| Today | |
| --- | --- |
| Nothing logged | [`today-1-nothing-logged.png`](gallery/today-1-nothing-logged.png) |
| Part logged | [`today-2-part-logged.png`](gallery/today-2-part-logged.png) |
| After a log, with Undo | [`today-3-after-a-log.png`](gallery/today-3-after-a-log.png) |
| Low lead | [`today-4-low-lead.png`](gallery/today-4-low-lead.png) |
| Complete | [`today-5-complete.png`](gallery/today-5-complete.png) |
| Caught | [`today-6-caught.png`](gallery/today-6-caught.png) |
| A log queued offline | [`today-7-queued-offline.png`](gallery/today-7-queued-offline.png) |
| The queued log delivered | [`today-8-queued-log-delivered.png`](gallery/today-8-queued-log-delivered.png) |

| Elsewhere | |
| --- | --- |
| Both widgets on the Home Screen | [`widgets-1-on-the-home-screen.png`](gallery/widgets-1-on-the-home-screen.png) |
| Both widgets after a Feed tap | [`widgets-2-after-a-feed-tap.png`](gallery/widgets-2-after-a-feed-tap.png) |
| Settings: day, reminders, profile | [`settings-1-day-reminders-profile.png`](gallery/settings-1-day-reminders-profile.png) |
| Settings: habits, keys, devices, account | [`settings-2-habits-keys-devices-account.png`](gallery/settings-2-habits-keys-devices-account.png) |
| Settings: keys | [`settings-3-keys.png`](gallery/settings-3-keys.png) |
| Settings: a new MCP key and its command | [`settings-4-new-mcp-key.png`](gallery/settings-4-new-mcp-key.png) |
| Settings: reminders on, with the no-token notice | [`settings-5-reminders-on.png`](gallery/settings-5-reminders-on.png) |
| The Shortcuts actions | [`shortcuts-actions.png`](gallery/shortcuts-actions.png) |
| A reminder, delivered by `simctl` | [`reminder-delivered-by-simctl.png`](gallery/reminder-delivered-by-simctl.png) |
| The public profile | [`profile-matt.png`](gallery/profile-matt.png) |

The key in the MCP key screenshot belonged to a throwaway local database and no longer exists.

## What the demo does not show

Simulator evidence is evidence, not acceptance (PRD, TDD §0.1 E2). These wait for Matt's check
on a real phone, or for credentials only he can provide:

- **A real phone.** Everything ran in the simulator.
- **APNs delivery.** The simulator has no `aps-environment` entitlement, so it gets no push
  token (Settings says so). Scene 9 registers the installation through the API with a
  placeholder token, and the reminder is delivered by `simctl`. Widget refresh by push is not
  built (TDD §0.2).
- **The Lock Screen** and its widget families.
- **Auth0.** Every sign-in is the development sign-in.
- **Background delivery.** The queued log in scene 8 is sent when the app refreshes in the
  foreground.
- **120 Hz playback.** The simulator records at its own rate, and the video is 30 frames a
  second.
- **Two Today states** from the snapshot list: a short day at night and an out-of-date chase.
  The snapshot tests cover them; the demo runs in the day against a live server.
