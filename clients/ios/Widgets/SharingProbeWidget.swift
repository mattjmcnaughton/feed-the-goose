import GooseCore
import SwiftUI
import WidgetKit

/// A placeholder widget that shows the value the app wrote to the App Group and to the
/// Keychain, and whether it could read each. Debug builds only: `SharingUITests` adds it.
struct SharingProbeEntry: TimelineEntry {
	let date: Date
	let appGroup: String
	let keychain: String
}

struct SharingProbeProvider: TimelineProvider {
	func placeholder(in context: Context) -> SharingProbeEntry {
		SharingProbeEntry(date: .now, appGroup: "…", keychain: "…")
	}

	func getSnapshot(in context: Context, completion: @escaping (SharingProbeEntry) -> Void) {
		completion(read())
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<SharingProbeEntry>) -> Void) {
		completion(Timeline(entries: [read()], policy: .never))
	}

	private func read() -> SharingProbeEntry {
		guard let probe = SharingProbe(infoDictionary: Bundle.main.infoDictionary) else {
			return SharingProbeEntry(date: .now, appGroup: "not configured", keychain: "not configured")
		}
		return SharingProbeEntry(date: .now, appGroup: describe(probe.readAppGroup()), keychain: describe(probe.readKeychain()))
	}

	private func describe(_ result: Result<String, SharingProbe.Failure>) -> String {
		switch result {
		case let .success(value): value
		case let .failure(failure): "✗ \(failure)"
		}
	}
}

struct SharingProbeWidgetView: View {
	let entry: SharingProbeEntry

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Sharing probe").font(.headline)
			LabeledContent("App Group", value: entry.appGroup)
			LabeledContent("Keychain", value: entry.keychain)
		}
		.font(.caption)
		.containerBackground(.white, for: .widget)
	}
}

struct SharingProbeWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "SharingProbe", provider: SharingProbeProvider()) { entry in
			SharingProbeWidgetView(entry: entry)
		}
		.configurationDisplayName("Sharing probe")
		.description("Shows what the app wrote to the App Group and the Keychain.")
		.supportedFamilies([.systemMedium])
	}
}
