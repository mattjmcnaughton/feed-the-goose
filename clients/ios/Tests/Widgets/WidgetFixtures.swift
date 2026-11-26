import Foundation
import GooseCore
@testable import FeedTheGoose

/// The example day's chase (lead 80 at 6 PM New York time, day ending at midnight), with
/// whatever a test changes, received at `receivedAt`.
enum WidgetFixtures {
	static let newYork: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/New_York")!
		calendar.locale = Locale(identifier: "en_US")
		return calendar
	}()

	static let chase: Chase = try! Fixtures.load("example-day-07-chase").response()

	static func date(_ iso: String) -> Date {
		try! Date(iso, strategy: .iso8601)
	}

	static func snapshot(
		receivedAt: Date = chase.asOf, isOutOfDate: Bool = false, _ change: (inout Chase) -> Void = { _ in }
	) -> ChaseSnapshot {
		var chase = chase
		change(&chase)
		return ChaseSnapshot(chase: chase, receivedAt: receivedAt, isOutOfDate: isOutOfDate)
	}

	/// Every state the widgets draw, by name, as each widget's first entry.
	static var states: [(name: String, entry: ChaseEntry)] {
		let now = chase.asOf
		func first(_ snapshot: ChaseSnapshot?, signedIn: Bool = true, at time: Date = now) -> ChaseEntry {
			WidgetContent.timeline(snapshot: snapshot, signedIn: signedIn, now: time, calendar: newYork).entries[0]
		}
		return [
			("running", first(snapshot())),
			("low-lead", first(snapshot { $0.lead = 18 })),
			("complete", first(snapshot {
				$0.state = .complete
				$0.lead = 113
				for i in $0.habits.indices { $0.habits[i].done = true; $0.habits[i].logged = $0.habits[i].target }
			})),
			("short", first(snapshot(receivedAt: date("2026-11-27T05:00:00Z")) {
				$0.state = .short
				$0.lead = 12
				$0.asOf = date("2026-11-27T05:00:00Z")
			})),
			("caught", first(snapshot(receivedAt: date("2026-11-27T02:45:00Z")) {
				$0.state = .caught
				$0.lead = 0
				$0.asOf = date("2026-11-27T02:45:00Z")
				$0.caughtAt = date("2026-11-27T02:41:00Z")
			}, at: date("2026-11-27T02:45:00Z"))),
			("signed-out", first(snapshot(), signedIn: false)),
			("no-chase", first(nil)),
			("out-of-date", first(snapshot(isOutOfDate: true), at: now + 2 * 3600)),
		]
	}
}
