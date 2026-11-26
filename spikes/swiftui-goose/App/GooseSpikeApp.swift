import SwiftUI
import WidgetKit

@main
struct GooseSpikeApp: App {
	var body: some Scene {
		WindowGroup { ContentView() }
	}
}

/// Frame-interval stats for the last play, to judge smoothness.
final class FrameStats {
	var last: Double? = nil
	var intervals: [Double] = []
	var drawTimes: [Double] = []
	func reset() { last = nil; intervals = []; drawTimes = [] }
	func tick(_ now: Double) {
		if let l = last { intervals.append(now - l) }
		last = now
	}
	func summary(clip: String) -> String {
		guard !intervals.isEmpty else { return "\(clip): no frames" }
		let s = intervals.sorted()
		let mean = s.reduce(0, +) / Double(s.count)
		let p99 = s[min(s.count - 1, Int(Double(s.count) * 0.99))]
		let slow = s.filter { $0 > mean * 1.5 }.count
		let d = drawTimes.sorted()
		let dMean = d.isEmpty ? 0 : d.reduce(0, +) / Double(d.count)
		let dMax = d.last ?? 0
		return String(format: "%@: %d frames, mean %.2f ms (%.0f fps), p99 %.2f ms, max %.2f ms, >1.5x mean: %d; draw mean %.3f ms, max %.3f ms",
		              clip, s.count + 1, mean * 1000, 1 / mean, p99 * 1000, (s.last ?? 0) * 1000, slow, dMean * 1000, dMax * 1000)
	}
}

struct ContentView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var clip = SNAP
	@State private var start: Date? = nil
	@State private var still: Double = SNAP.poster
	@State private var stats = FrameStats()
	@State private var report = ""

	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				if let start {
					TimelineView(.animation) { tl in
						let t = tl.date.timeIntervalSince(start)
						let _ = stats.tick(tl.date.timeIntervalSinceReferenceDate)
						StageView(pose: clip.frame(min(t, clip.dur))) { stats.drawTimes.append($0) }
							.onChange(of: t >= clip.dur) { _, done in if done { finish() } }
					}
				} else {
					StageView(pose: clip.frame(still))
				}
				Picker("Clip", selection: Binding(get: { clip.id }, set: { id in play(CLIPS.first { $0.id == id }!) })) {
					ForEach(CLIPS) { Text($0.name).tag($0.id) }
				}
				.pickerStyle(.segmented)
				.frame(width: 340)
				Button("Replay") { play(clip) }.buttonStyle(.borderedProminent)
				Text(reduceMotion ? "Reduce Motion is on: each clip jumps to its last frame." : "Reduce Motion is off.")
					.font(.footnote).foregroundStyle(.secondary)
				Text(report).font(.caption2.monospaced()).frame(width: 340, alignment: .leading)
			}
			.padding(.top, 24)
			.frame(maxWidth: .infinity)
		}
		.background(Color(.systemBackground))
		.onAppear(perform: autorun)
	}

	private func play(_ c: Clip) {
		clip = c
		if reduceMotion {
			start = nil
			still = c.dur
			report = "\(c.name): Reduce Motion, showing the last frame"
			return
		}
		stats.reset()
		start = Date()
	}

	private func finish() {
		guard start != nil else { return }
		start = nil
		still = clip.dur
		report = stats.summary(clip: clip.name)
		print("STATS " + report)
	}

	/// Launch arguments for unattended runs:
	/// `-sheet` writes a 10-frame contact sheet per clip, `-play a,b,c` plays clips in turn.
	private func autorun() {
		let args = ProcessInfo.processInfo.arguments
		WidgetCenter.shared.reloadAllTimelines()
		if args.contains("-sheet") { writeSheets() }
		if let i = args.firstIndex(of: "-play"), i + 1 < args.count {
			let ids = args[i + 1].split(separator: ",").map(String.init)
			Task { @MainActor in
				try? await Task.sleep(for: .seconds(1.5))
				for id in ids {
					guard let c = CLIPS.first(where: { $0.id == id }) else { continue }
					play(c)
					try? await Task.sleep(for: .seconds(c.dur + 1.2))
				}
			}
		}
	}

	@MainActor private func writeSheets() {
		let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		for c in CLIPS {
			let n = 10
			let grid = VStack(spacing: 8) {
				ForEach(0..<2, id: \.self) { row in
					HStack(spacing: 8) {
						ForEach(0..<5, id: \.self) { col in
							StageView(pose: c.frame(c.dur * Double(row * 5 + col) / Double(n - 1)))
						}
					}
				}
			}
			.padding(4).background(Color.gray)
			let r = ImageRenderer(content: grid)
			r.scale = 1
			if let img = r.uiImage, let data = img.pngData() {
				try? data.write(to: dir.appendingPathComponent("\(c.id)-frames.png"))
			}
		}
		print("SHEETS " + dir.path)
	}
}
