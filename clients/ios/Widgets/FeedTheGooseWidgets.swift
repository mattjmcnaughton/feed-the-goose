import GooseCore
import SwiftUI
import WidgetKit

/// Reads the chase cached in the App Group. A new timeline fetches the chase first when the
/// cached one is missing, out of date or past its timeline's end (TDD §6.7). Both widgets use it.
struct ChaseProvider: TimelineProvider {
	func placeholder(in context: Context) -> ChaseEntry {
		ChaseEntry(date: .now, shown: .chase(ShownChase(state: .running, lead: 80, hour: 18, stage: 2, caughtAt: nil, age: nil, open: [])))
	}

	/// The gallery's preview: the cache as it is, without the network.
	func getSnapshot(in context: Context, completion: @escaping (ChaseEntry) -> Void) {
		let reply = Reply(completion)
		Task { @MainActor in reply.send(Self.cachedTimeline().entries[0]) }
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<ChaseEntry>) -> Void) {
		let reply = Reply(completion)
		Task { @MainActor in
			let timeline = await Self.timelineFetching()
			reply.send(Timeline(entries: timeline.entries, policy: timeline.reloadAt.map { .after($0) } ?? .never))
		}
	}

	@MainActor
	private static func timelineFetching() async -> (entries: [ChaseEntry], reloadAt: Date?) {
		// A fetch here must not reload the widgets, or each new timeline would ask for another.
		guard let environment = IntentEnvironment.make(reloadsWidgets: false) else { return cachedTimeline() }
		let signedIn = ChaseActions.isSignedIn(environment)
		let now = Date()
		if signedIn, environment.chaseStore.snapshot.map({ $0.isOutOfDate || WidgetContent.timelineEnd($0) <= now }) ?? true {
			await environment.chaseStore.refresh()
		}
		return WidgetContent.timeline(snapshot: environment.chaseStore.snapshot, signedIn: signedIn, now: Date())
	}

	@MainActor
	private static func cachedTimeline() -> (entries: [ChaseEntry], reloadAt: Date?) {
		guard let environment = IntentEnvironment.make(reloadsWidgets: false) else {
			return ([ChaseEntry(date: .now, shown: .noChase)], nil)
		}
		return WidgetContent.timeline(snapshot: environment.shared.chaseSnapshot, signedIn: ChaseActions.isSignedIn(environment), now: Date())
	}
}

/// WidgetKit's completion handlers are not `Sendable`, but WidgetKit allows calling them from
/// any thread.
private struct Reply<Value>: @unchecked Sendable {
	let send: (Value) -> Void
	init(_ send: @escaping (Value) -> Void) { self.send = send }
}

struct ChaseWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "Chase", provider: ChaseProvider()) { entry in
			ChaseEntryView(entry: entry)
		}
		.configurationDisplayName("Chase")
		.description("How far behind you the goose is.")
		.supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
		.contentMarginsDisabled()
	}
}

struct FeedWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "Feed", provider: ChaseProvider()) { entry in
			FeedEntryView(entry: entry)
		}
		.configurationDisplayName("Feed")
		.description("Log a habit without opening the app.")
		.supportedFamilies([.systemSmall, .systemMedium])
		.contentMarginsDisabled()
	}
}

private struct ChaseEntryView: View {
	@Environment(\.widgetFamily) private var family
	let entry: ChaseEntry
	var body: some View { ChaseWidgetView(entry: entry, family: family) }
}

private struct FeedEntryView: View {
	@Environment(\.widgetFamily) private var family
	let entry: ChaseEntry
	var body: some View { FeedWidgetView(entry: entry, family: family) }
}

@main
struct FeedTheGooseWidgets: WidgetBundle {
	var body: some Widget {
		#if DEBUG
			// T11's sharing UI test adds the gallery's first widget, so the probe comes first.
			// Release builds leave it out.
			SharingProbeWidget()
		#endif
		ChaseWidget()
		FeedWidget()
	}
}
