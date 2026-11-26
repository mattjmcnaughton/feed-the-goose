# Recording the end-to-end demo

How to reproduce [`docs/demo/v1-demo.mp4`](../demo/v1-demo.mp4) from a clean orb and Mac
satellite (TDD §8, ticket T20). Every frame is the real app in the iOS Simulator talking to the
real backend on the orb. Nothing is a fixture: the scenes seed their accounts with
`POST /dev/seed` and the server computes every lead, streak and result (constitution §1).

The scripts are in `clients/ios/scripts/demo/`:

| Script | Runs on | Does |
| --- | --- | --- |
| `orb.sh` | Orb | Starts the backend, and does the steps outside the phone: the MCP call, stopping and starting the web service, the profile capture. |
| `scene.sh` | Mac | Erases and boots the simulator and builds the tests (`setup`), then records one scene at a time with `UITests/DemoTests.swift`. |
| `join.sh` | Orb | Joins the clips into one video with a title card before each scene. |

## When

Record during the simulator's day. The satellite's clock zone is GMT, so set the Mac to the
seed's zone first; the seeded days are placed relative to the real time, so any hour from about
07:00 to 22:00 in `America/New_York` works. A new account has no chase between 00:00 and 06:00.

## 1. The orb

From the repository root, on `v1-build`:

```sh
bash .agents/setup
clients/ios/scripts/demo/orb.sh backend
```

`backend` starts `dockerd`, Postgres, the migrations, the web service and the worker as orb
services. The web service runs `just dev` with:

- `ALLOWED_EMAILS` holding the demo's five accounts (`new@`, `matt@`, `caught@`, `offline@` and
  `remind@example.com`) and the UI tests' two;
- `REMINDER_BEFORE_SECONDS=30`, so a reminder comes 30 seconds before the catch instead of an
  hour, and scene 9 fits in the recording;
- `UVICORN_TIMEOUT_KEEP_ALIVE=300`. Uvicorn closes an idle connection after 5 seconds, and the
  satellite's port forward passes the close on late, so the app sends the next PUT on a dead
  connection and iOS reports -1005 without retrying it. Scene 9 hit this when turning
  reminders on.

It prints `GET http://localhost:8000/readyz -> 200` when the web service is up.

## 2. The Mac

Start the satellite with `image: macos-26` and `forward_ports: ["8000:8000"]`, then:

```sh
brew install xcodegen just
sudo systemsetup -settimezone America/New_York
cd clients/ios
scripts/demo/scene.sh setup
```

`setup` generates the project, erases and boots the `iPhone 17 Pro` on iOS 26.2, and builds the
app and the tests. Each scene checks `localhost:8000/readyz` first.

## 3. The scenes

Run them in order on the same simulator: each starts where the last left the app and the Home
Screen. Clips and screenshots go to `$FTG_DEMO_OUT` (default `/tmp/ftg-demo-out`).

`DemoTests` runs only when `FTG_DEMO=1`, which `scene.sh` sets, so `just ios-uitest` skips it.
The recording starts when the test is ready, at its `record` cue.

| # | Command | Steps outside the phone |
| --- | --- | --- |
| 1 | `scripts/demo/scene.sh 1` | None |
| 2 | `scripts/demo/scene.sh 2` | None |
| 3 | `scripts/demo/scene.sh 3` | None. Adding widgets taps coordinates, as `WidgetTests` does; if it misses, run `setup` and scenes 1 to 3 again. |
| 4 | `scripts/demo/scene.sh 4` | At the `mcp` cue, on the orb: `scripts/demo/orb.sh mcp <key>`, with the key the app wrote to `/tmp/ftg-demo/mcp-key` on the Mac. Then `touch /tmp/ftg-demo/go-mcp` on the Mac. |
| 5 | `scripts/demo/scene.sh 5` | None |
| 6 | `scripts/demo/orb.sh profile` on the orb | It captures `/matt` at 2x and fails if a habit name is on the page. |
| — | `scripts/demo/scene.sh gallery` | None. Screenshots of Settings and the Shortcuts actions, not recorded. |
| 7 | `scripts/demo/scene.sh 7` | None. The account is caught about a minute after seeding. |
| 8 | `scripts/demo/scene.sh 8` | At `offline`: `orb.sh offline`, then `touch /tmp/ftg-demo/go-offline`. At `online`: `orb.sh online`, then `touch /tmp/ftg-demo/go-online`. Afterwards, `orb.sh logs` prints the stored log's `logged_at`. |
| 9 | `scripts/demo/scene.sh 9` | None: `scene.sh` answers the `push` cue itself by reading `GET /dev/pushes` and running `xcrun simctl push`. It takes about two minutes. |

A scene waiting on a cue prints what to do. Each cue waits up to five minutes.

Scene 9 needs two stand-ins, because the simulator has no `aps-environment` entitlement and so
gets no push token: the test registers the installation through `PUT /v1/me/devices` with a
placeholder token, which the recording sender accepts, and the reminder is delivered by
`simctl`, not by APNs.

## 4. The video

Copy the Mac's `$FTG_DEMO_OUT` to the orb with `mac_download`, then:

```sh
clients/ios/scripts/demo/join.sh <copied folder> .amp/in/artifacts/T20/06-profile.png
```

It writes `docs/demo/v1-demo.mp4` at 600 pixels wide, H.264, `-crf 24`, and prints where each
scene starts. Scenes 7 and 9 play at 2× because they wait for the pursuer and the worker.

The simulator's H.264 has B-frames whose decode times lag their presentation times by up to
several seconds. `join.sh` therefore decodes every frame and times it by its presentation time;
resampling the clip with ffmpeg's `fps` filter drops whole stretches, such as the end of scene 8.

## 5. Check it

Watch the whole video and check every scene against TDD §8.2's "Shows" column. One frame every
few seconds in a contact sheet is a quick first pass:

```sh
ffmpeg -i docs/demo/v1-demo.mp4 -vf "fps=1/3,scale=150:-2" /tmp/frames/f%03d.png
magick montage /tmp/frames/f*.png -tile 15x -geometry +2+2 /tmp/sheet.png
```

A scene that did not show what it claims is recorded again, never left in.
