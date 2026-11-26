#if DEBUG
	import GooseRig
	import SwiftUI

	/// Shown instead of the root with the `-FTGRigGallery` launch argument: the rig's clips, its
	/// still poses at each stage, and the scene at the app's and the widgets' aspects.
	///
	/// More launch arguments, for unattended captures:
	/// - `-FTGRigPage clips|stages|aspects` opens a page; `-FTGRigStage 0...4` picks the stage.
	/// - `-FTGRigPlay snap,feast,peck` plays the clips in turn and prints frame-interval figures.
	/// - `-FTGRigSheets` writes a ten-frame contact sheet per clip to Documents.
	struct RigGalleryView: View {
		enum Page: String, CaseIterable { case clips, stages, aspects }

		@State private var page = Page(rawValue: UserDefaults.standard.string(forKey: "FTGRigPage") ?? "") ?? .clips

		var body: some View {
			VStack(spacing: 12) {
				Text("Rig gallery").font(.title2.bold())
				Picker("Page", selection: $page) {
					ForEach(Page.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
				}
				.pickerStyle(.segmented)
				switch page {
				case .clips: ClipsPage()
				case .stages: StagesPage()
				case .aspects: AspectsPage()
				}
				Spacer(minLength: 0)
			}
			.padding(.horizontal)
			.background(Color(white: 0.93))
		}
	}

	// MARK: Clips

	/// Frame intervals for the last play, to judge smoothness.
	final class FrameStats {
		var last: Date?
		var intervals: [Double] = []
		func reset() { last = nil; intervals = [] }
		func tick(_ now: Date) {
			if let last { intervals.append(now.timeIntervalSince(last)) }
			last = now
		}
		func summary(_ clip: String) -> String {
			guard !intervals.isEmpty else { return "\(clip): no frames" }
			let s = intervals.sorted()
			let mean = s.reduce(0, +) / Double(s.count)
			let p99 = s[min(s.count - 1, Int(Double(s.count) * 0.99))]
			let slow = s.filter { $0 > mean * 1.5 }.count
			return String(format: "%@: %d frames, mean %.2f ms (%.0f fps), p99 %.2f ms, max %.2f ms, >1.5x mean: %d",
			              clip, s.count + 1, mean * 1000, 1 / mean, p99 * 1000, s[s.count - 1] * 1000, slow)
		}
	}

	private struct ClipsPage: View {
		@Environment(\.accessibilityReduceMotion) private var reduceMotion
		@State private var clip = Clip.snapExample
		@State private var start = Date.distantPast
		@State private var stats = FrameStats()
		@State private var report = ""

		var body: some View {
			VStack(spacing: 12) {
				ClipPlayer(clip: clip, start: start) { pose, t in
					let _ = stats.tick(.now)
					StageCard(pose: pose, caption: clip.caption(at: t))
						.onChange(of: t >= clip.duration) { _, done in if done { finish() } }
				}
				Picker("Clip", selection: Binding(get: { clip.id }, set: { id in play(id) })) {
					ForEach(Clip.examples) { Text($0.name).tag($0.id) }
				}
				.pickerStyle(.segmented)
				.frame(width: 340)
				Button("Replay") { play(clip.id) }.buttonStyle(.borderedProminent)
				Text(reduceMotion ? "Reduce Motion is on: each clip shows its last frame." : "Reduce Motion is off.")
					.font(.footnote).foregroundStyle(.secondary)
					.accessibilityIdentifier("rig.reduceMotion")
				Text(report).font(.caption2.monospaced()).frame(width: 340, alignment: .leading)
			}
			.onAppear(perform: autorun)
		}

		private func play(_ id: String) {
			guard let next = Clip.examples.first(where: { $0.id == id }) else { return }
			clip = next
			report = reduceMotion ? "\(next.name): Reduce Motion, showing the last frame" : ""
			stats.reset()
			start = .now
		}

		private func finish() {
			guard !reduceMotion, stats.last != nil else { return }
			report = stats.summary(clip.name)
			print("FTGRigStats " + report)
			stats.reset()
		}

		private func autorun() {
			let args = ProcessInfo.processInfo.arguments
			if args.contains("-FTGRigSheets") { writeSheets() }
			guard let ids = UserDefaults.standard.string(forKey: "FTGRigPlay") else { return }
			Task { @MainActor in
				try? await Task.sleep(for: .seconds(1.5))
				for id in ids.split(separator: ",").map(String.init) {
					guard let c = Clip.examples.first(where: { $0.id == id }) else { continue }
					play(id)
					try? await Task.sleep(for: .seconds(c.duration + 1.2))
				}
			}
		}

		/// The same ten times as docs/prototypes/tools/frames-animations.sh: 0 to the clip's
		/// length in nine equal steps, two rows of five.
		@MainActor private func writeSheets() {
			let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			for c in Clip.examples {
				let grid = VStack(spacing: 8) {
					ForEach(0..<2, id: \.self) { row in
						HStack(spacing: 8) {
							ForEach(0..<5, id: \.self) { col in
								let t = c.duration * Double(row * 5 + col) / 9
								StageCard(pose: c.pose(at: t), caption: c.caption(at: t))
							}
						}
					}
				}
				.padding(4).background(Color(white: 0.53))
				let r = ImageRenderer(content: grid)
				r.scale = 2
				if let data = r.uiImage?.pngData() {
					try? data.write(to: dir.appendingPathComponent("\(c.id)-frames.png"))
				}
			}
			print("FTGRigSheets " + dir.path)
		}
	}

	// MARK: Stages

	private struct StagesPage: View {
		@State private var stage = Stage(rawValue: UserDefaults.standard.integer(forKey: "FTGRigStage")) ?? .gosling

		var body: some View {
			VStack(spacing: 10) {
				Picker("Stage", selection: $stage) {
					ForEach(Stage.allCases, id: \.self) { Text("\($0.rawValue)").tag($0) }
				}
				.pickerStyle(.segmented)
				Text("Stage \(stage.rawValue): \(stage.name)").font(.headline)
				Grid(horizontalSpacing: 8, verticalSpacing: 8) {
					GridRow {
						still("Running, 80 steps, 6 pm", .running(lead: 0.8, hour: 18, stage: stage))
						still("Complete, 6 pm", .complete(lead: 0.45, hour: 18, stage: stage))
					}
					GridRow {
						still("Short, 47 steps, midnight", .short(lead: 0.47, hour: 24, stage: stage))
						still("Caught, midnight", .caught(hour: 24, stage: stage))
					}
					GridRow {
						still("Running, 20 steps, 9 am", .running(lead: 0.2, hour: 9, stage: stage))
						still("Running, 0 steps, 8 pm", .running(lead: 0, hour: 20, stage: stage))
					}
				}
			}
		}

		private func still(_ label: String, _ pose: Pose) -> some View {
			VStack(alignment: .leading, spacing: 2) {
				SceneCanvas(pose: pose)
					.aspectRatio(SceneCanvas.sceneSize, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 8))
				Text(label).font(.caption2)
			}
		}
	}

	// MARK: Aspects

	/// The same pose in the frames the app and the widgets give the scene. The widget sizes are
	/// an iPhone 17 Pro's (small 170 x 170, medium 364 x 170) less a 61-point readout.
	private struct AspectsPage: View {
		@State private var state = 0
		private var pose: Pose {
			[
				Pose.running(lead: 0.8, hour: 18, stage: .bigGoose),
				.complete(lead: 0.45, hour: 12, stage: .giantGoose),
				.caught(hour: 24, stage: .gosling),
			][state]
		}

		var body: some View {
			VStack(alignment: .leading, spacing: 10) {
				Picker("State", selection: $state) {
					Text("Running").tag(0)
					Text("Complete").tag(1)
					Text("Caught").tag(2)
				}
				.pickerStyle(.segmented)
				framed("App, full width at 340:176", SceneCanvas(pose: pose).aspectRatio(SceneCanvas.sceneSize, contentMode: .fit))
				framed("Medium widget, 364 x 109", SceneCanvas(pose: pose).frame(width: 364, height: 109))
				framed("Small widget, 170 x 109", SceneCanvas(pose: pose).frame(width: 170, height: 109))
			}
			.onAppear { state = UserDefaults.standard.integer(forKey: "FTGRigState") }
		}

		private func framed(_ label: String, _ scene: some View) -> some View {
			VStack(alignment: .leading, spacing: 2) {
				scene.overlay(Rectangle().stroke(Color.red, lineWidth: 1))
				Text(label).font(.caption)
			}
		}
	}
#endif
