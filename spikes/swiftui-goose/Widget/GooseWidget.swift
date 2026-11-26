import SwiftUI
import WidgetKit

// Widgets render snapshots, not animations, so the widget shows one static pose from the rig:
// the 6 pm chase with the goose 80 steps back, like docs/prototypes 04-app-screens' widget.

struct Entry: TimelineEntry { let date: Date; let lead: Double }

struct Provider: TimelineProvider {
	func placeholder(in context: Context) -> Entry { Entry(date: .now, lead: 0.8) }
	func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(placeholder(in: context)) }
	func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
		completion(Timeline(entries: [placeholder(in: context)], policy: .never))
	}
}

struct GooseWidgetView: View {
	let entry: Entry
	var body: some View {
		var pose = Pose()
		pose.gx = G(entry.lead)
		pose.phase = 1.1
		pose.scroll = 40
		return VStack(spacing: 0) {
			SceneCanvas(pose: pose, cropSky: true)
			Rectangle().fill(INK).frame(height: 3)
			HStack {
				VStack(alignment: .leading, spacing: 0) {
					Text("\(steps(entry.lead)) steps").font(.custom("Shrikhand-Regular", size: 20))
					Text("behind you").font(.system(size: 14, design: .rounded))
				}
				.foregroundStyle(INK)
				Spacer()
			}
			.padding(.horizontal, 14)
			.frame(height: 58)
		}
		.containerBackground(Color(hex: 0xfffaf0), for: .widget)
	}
}

@main
struct GooseWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "GooseWidget", provider: Provider()) { GooseWidgetView(entry: $0) }
			.configurationDisplayName("Feed the Goose")
			.description("How far back the goose is.")
			.supportedFamilies([.systemMedium])
			.contentMarginsDisabled()
	}
}
