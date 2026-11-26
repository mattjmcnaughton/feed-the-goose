# SwiftUI goose spike (throwaway)

This spike is not the app. It ports `docs/prototypes/src/rig.js` and three clips from
`05-animations` (Snap, Feast, Peck) to SwiftUI, to judge how risky native animation is. It also
shows one static pose in a WidgetKit widget.

```sh
brew install xcodegen
cd spikes/swiftui-goose && xcodegen generate
xcodebuild -project GooseSpike.xcodeproj -scheme GooseSpike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/dd build
```

Launch arguments: `-sheet` writes a 10-frame contact sheet per clip to the app's Documents
folder, using the same timestamps as `docs/prototypes/tools/frames-animations.sh`.
`-play snap,feast,peck` plays clips in turn and prints frame-interval stats. The
`GooseSpikeUITests` target drives Springboard to add the widget to the Home Screen.

| File | What |
| --- | --- |
| `Shared/Rig.swift` | The scene, goose, runner and props, drawn into a SwiftUI `GraphicsContext`. The counterpart of `draw(svg, pose)`. |
| `Shared/Clips.swift` | The keyframe helpers (`k`, `seg`, `pulse`, `arc`, `spray`, `halt`) and the three clips, as `(seconds) -> Pose`. |
| `Shared/SVGPath.swift` | A small parser for the rig's path strings. |
| `Shared/StageView.swift` | `SceneCanvas` (a `Canvas`) and the stage with its readout. |
| `App/` | `TimelineView(.animation)` playback, Reduce Motion, frame stats, and the contact sheet export. |
| `Widget/` | A medium widget showing one static pose. |

## Findings (2026-11-25, Xcode 27.3, iOS Simulator, iPhone 17 Pro)

- **Fidelity:** The 30 sampled frames match the prototype's contact sheets pose for pose. The
  sampled frames are 10 per clip, from both the offline renders and the screen recording. The
  only differences are text metrics. Shrikhand's line height in SwiftUI `Text` is taller than
  in CSS, and the readout wraps at different points. In one Feast frame the crumbs are missing
  at exactly t = 2.40 s, where `spray`'s 0.5 s cut-off falls on a floating-point boundary.
- **Smoothness:** Playback is a steady 60 fps (mean frame interval 16.7 ms) in the simulator.
  Each run has one long interval, on the first frame. Building a frame's draw commands in the
  `Canvas` closure takes under 0.1 ms on average. This was not measured on a device or at
  120 Hz ProMotion.
- **Effort:** The port took about 20 minutes and about 530 lines (rig 322, clips 152, path
  parser 38, canvas 61). The clips ported almost line for line from JavaScript.
- **What needed care:** Canvas doesn't clip to its frame the way an SVG viewBox does. Outlined
  text (`paint-order="stroke"`) needs glyph paths from Core Text. The rig's fixed 340-unit
  frame had to be widened to fill the widget's aspect. Springboard's widget gallery hides its
  controls from XCUITest, so the test taps coordinates.
