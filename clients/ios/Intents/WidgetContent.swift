import Foundation
import GooseCore
import WidgetKit

// What the widgets show, worked out from the chase cached in the App Group. It lives in
// `Intents/`, which the app compiles too, so the timeline and the views are tested in the app's
// test target. The widget extension adds only the providers and the widget definitions.

/// One moment of a widget's timeline.
struct ChaseEntry: TimelineEntry, Hashable {
	let date: Date
	let shown: Shown
}

enum Shown: Hashable {
	/// No session token: both widgets say "Open Feed the Goose".
	case signedOut
	/// Signed in, but no chase is cached yet, or the user has no habits.
	case noChase
	case chase(ShownChase)
}

/// A chase at one entry's time, as plain values for the views.
struct ShownChase: Hashable {
	var state: ChaseState
	/// The lead at the entry's time, extrapolated with `ChaseClock` while the day runs.
	var lead: Double
	/// The local time of day for the sky, from 6 to 24.
	var hour: Double
	var stage: Int
	/// When the day was caught, as local time, such as "9:41 PM".
	var caughtAt: String?
	/// Set when the chase is out of date: how long ago it arrived, such as "2 hr".
	var age: String?
	/// The habits not finished yet, in position order, for the Feed widget's buttons.
	var open: [ChaseHabit]
}

enum WidgetContent {
	/// The time between entries while a day runs (TDD §6.7).
	static let interval: TimeInterval = 15 * 60

	/// The entries from `now`, and when to ask for a new timeline (nil: only when the app says).
	///
	/// While the day runs there is an entry every 15 minutes up to the earliest of `caught_at`,
	/// `day_ends_at` and `next_day_starts_at`, with one at that time. The new timeline then
	/// fetches the chase. An entry at `caught_at` shows a lead of 0 but stays running: only the
	/// server says a day is caught. A day that is over shows one entry until the next day starts.
	static func timeline(
		snapshot: ChaseSnapshot?, signedIn: Bool, now: Date, calendar: Calendar = .current
	) -> (entries: [ChaseEntry], reloadAt: Date?) {
		guard signedIn else { return ([ChaseEntry(date: now, shown: .signedOut)], nil) }
		guard let snapshot else { return ([ChaseEntry(date: now, shown: .noChase)], now + interval) }
		let end = timelineEnd(snapshot)
		if snapshot.isOutOfDate || end <= now {
			return ([entry(snapshot, at: now, stale: true, calendar: calendar)], now + interval)
		}
		guard snapshot.chase.state == .running else {
			return ([entry(snapshot, at: now, stale: false, calendar: calendar)], end)
		}
		var dates = Array(stride(from: now, to: end, by: interval))
		dates.append(end)
		return (dates.map { entry(snapshot, at: $0, stale: false, calendar: calendar) }, end)
	}

	/// The device time at which the cached chase needs fetching again.
	static func timelineEnd(_ snapshot: ChaseSnapshot) -> Date {
		let clock = snapshot.clock
		let chase = snapshot.chase
		var end = clock.deviceTime(of: chase.nextDayStartsAt)
		if chase.state == .running {
			end = min(end, clock.deviceTime(of: chase.dayEndsAt))
			if let caughtAt = chase.caughtAt { end = min(end, clock.deviceTime(of: caughtAt)) }
		}
		return end
	}

	static func entry(_ snapshot: ChaseSnapshot, at date: Date, stale: Bool, calendar: Calendar = .current) -> ChaseEntry {
		let chase = snapshot.chase
		let clock = snapshot.clock
		let dayEnd = clock.deviceTime(of: chase.dayEndsAt)
		let skyTime: Date = switch chase.state {
		case .running: min(date, dayEnd)
		case .short: dayEnd
		case .caught: clock.deviceTime(of: chase.caughtAt ?? chase.asOf)
		case .complete: min(snapshot.receivedAt, dayEnd)
		}
		var caughtAt: String?
		if chase.state == .caught, let at = chase.caughtAt {
			let format = Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
			caughtAt = clock.deviceTime(of: at).formatted(format)
		}
		let shown = ShownChase(
			state: chase.state,
			lead: clock.lead(at: date),
			hour: hour(of: skyTime, calendar: calendar),
			stage: chase.streak.stage,
			caughtAt: caughtAt,
			age: stale ? age(of: snapshot, at: date) : nil,
			open: chase.habits.filter { !$0.done }
		)
		return ChaseEntry(date: date, shown: .chase(shown))
	}

	/// The local time of day, with the small hours after midnight counted as 24 and over.
	static func hour(of date: Date, calendar: Calendar) -> Double {
		let parts = calendar.dateComponents([.hour, .minute], from: date)
		let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
		return min(24, max(6, hour < 6 ? hour + 24 : hour))
	}

	/// "80 steps", "1 step".
	static func steps(_ lead: Double) -> String {
		let n = Int(lead.rounded())
		return n == 1 ? "1 step" : "\(n) steps"
	}

	/// How long ago a chase arrived, such as "5 min", "2 hr" or "3 days".
	static func age(of snapshot: ChaseSnapshot, at now: Date) -> String {
		let minutes = Int(max(0, now.timeIntervalSince(snapshot.receivedAt)) / 60)
		if minutes < 1 { return "less than a minute" }
		if minutes < 60 { return "\(minutes) min" }
		if minutes < 48 * 60 { return "\(minutes / 60) hr" }
		return "\(minutes / (24 * 60)) days"
	}
}
