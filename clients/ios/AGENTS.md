# iOS app guidance

The SwiftUI app, the widget extension and the App Intents. Architecture: TDD §6
(`docs/technical/tdds/01-v1.md`). Read the repository's `AGENTS.md` and the constitution first.

## The Mac

iOS work runs on a Mac satellite. Edit files on the orb; the Mac mirrors the worktree one way.

- Start it with `mac_sidecar` `start`, `image: macos-26`. The default `macos-27` image has no
  iOS 26 simulators. To reach the orb's backend, add `forward_ports: ["8000:8000"]`: the orb's
  port 8000 then answers at `http://localhost:8000` on the Mac, which the simulator shares, and
  that is the debug build's default `FTGAPIBaseURL`.
- Install the tools once per Mac: `brew install xcodegen just`. XcodeGen 2.45.1 (Homebrew) and
  just 1.46.0 were used for T11.
- The satellite is billed and stops after about 20 idle minutes. Start it only for iOS work.

## Pins

| What | Pin |
| --- | --- |
| Xcode | 26.3 (17C529), at the path in `.xcode-version`. The justfile sets `DEVELOPER_DIR` from it. |
| Simulator | `iPhone 17 Pro` on iOS 26.2. `scripts/simulator-udid.sh` finds its UDID. |
| Swift | 6 language mode; packages use tools version 6.2 (needed for `.iOS(.v26)`). |
| Deployment target | iOS 26.0, iPhone only, portrait, light mode only. |

## Commands

Run from `clients/ios/` on the Mac.

| Command | What |
| --- | --- |
| `just ios-generate` | Generates `FeedTheGoose.xcodeproj` from `project.yml`. Never commit the project. |
| `just ios-build` | Builds the app and the widget extension for the pinned simulator. |
| `just ios-test` | Unit and package tests. The merge gate for an iOS ticket. |
| `just ios-uitest` | UI tests, including the sharing test that adds the widget to the Home Screen. |
| `just ios-boot`, `just ios-install` | Boots the pinned simulator; installs the last build. |
| `just ios-screenshot name` | Saves a screenshot to `$FTG_CAPTURE_DIR` (default `/tmp/ftg-captures`). |

UI tests write their screenshots to the same folder. Copy captures to the orb with
`mac_download` and keep them under `.amp/in/artifacts/<ticket>/`. Open every capture before
reporting.

## Project rules

- `project.yml` is the source of the project and of both entitlements files. Sources are found
  by folder, so adding a file needs no edit. Edit the entitlements in `project.yml`
  (`x-sharing`): XcodeGen rewrites the `.entitlements` files from it.
- Targets: `FeedTheGoose` (`App/`, `Intents/`), `FeedTheGooseWidgets` (`Widgets/`, `Intents/`),
  `FeedTheGooseTests` (`Tests/`), `FeedTheGooseUITests` (`UITests/`).
- Packages: `GooseCore` (Foundation only), `GooseAPI` (generated client and live services),
  `GooseRig` (SwiftUI only). Only `App/LiveEnvironment.swift` and its twin in the extension
  import `GooseAPI`.
- Third-party Swift packages are pinned with exact versions. Only those in TDD §9 are allowed.
- Launch arguments: `-FTGAPIBaseURL <url>` (any build); in debug builds `-FTGRigGallery` and
  `-FTGSharingProbe <value>` (writes the value for the sharing test).

## Sharing without a signing team

Checked by T11 on 2026-11-26 with Xcode 26.3 and iOS 26.2: an ad hoc signed simulator build
shares the App Group and the Keychain access group between the app and the widget extension.
Xcode links the entitlements into each binary, with `FAKETEAMID` as the team prefix. With
the entitlements removed, the widget gets no App Group container and Keychain error -34018,
so the sharing test fails. A real device still needs a signing team.

## Capturing

From TDD §8.3. `$UDID` is `scripts/simulator-udid.sh 'iPhone 17 Pro' 26.2`.

```sh
xcrun simctl boot $UDID 2>/dev/null || true; xcrun simctl bootstatus $UDID
xcrun simctl install $UDID build/DerivedData/Build/Products/Debug-iphonesimulator/FeedTheGoose.app
xcrun simctl io $UDID recordVideo --codec h264 --force /tmp/out/scene.mp4 >/tmp/rec.log 2>&1 &
REC=$!; sleep 2
# drive the scene, then:
kill -INT $REC; wait $REC
xcrun simctl io $UDID screenshot /tmp/out/scene.png
```

Springboard hides the widget gallery's controls from the accessibility tree, so adding a
widget taps coordinates, as `UITests/SharingUITests.swift` does. `ffmpeg` and `magick` are on
the orb, not on the Mac.
