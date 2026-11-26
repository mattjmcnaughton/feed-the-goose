import Foundation
import GooseCore
import Testing
@testable import FeedTheGoose

/// The widgets' timeline (TDD §6.7). Expected values are worked out by hand from the example
/// day: lead 80 at 23:00Z, 5.56 steps an hour, the day ending at 05:00Z and the next starting
/// at 11:00Z.
struct WidgetTimelineTests {
	typealias F = WidgetFixtures

	func chases(_ entries: [ChaseEntry]) -> [ShownChase] {
		entries.compactMap { if case let .chase(chase) = $0.shown { chase } else { nil } }
	}

	@Test func aRunningDayHasAnEntryEveryQuarterHourUntilTheDayEnds() {
		// The device clock is five minutes fast: times follow the receipt, not the server.
		let received = F.chase.asOf + 300
		let (entries, reloadAt) = WidgetContent.timeline(snapshot: F.snapshot(receivedAt: received), signedIn: true, now: received, calendar: F.newYork)
		// Six hours to the day's end: 0, 15, …, 360 minutes.
		#expect(entries.count == 25)
		#expect(entries.first?.date == received)
		#expect(entries.last?.date == received + 6 * 3600)
		#expect(reloadAt == received + 6 * 3600)
		let shown = chases(entries)
		#expect(abs(shown[4].lead - (80 - 5.56)) < 0.001)
		// 80 − 5.56 × 6 = 46.64 at the end, and the sky at midnight.
		#expect(abs(shown.last!.lead - 46.64) < 0.001)
		#expect(abs(shown.first!.hour - (18 + 5.0 / 60)) < 0.001)
		#expect(shown.last?.hour == 24)
	}

	@Test func entriesStopAtTheCatchAndNeverSayCaught() {
		// 11.12 steps at 5.56 an hour is caught two hours later.
		let snapshot = F.snapshot {
			$0.lead = 11.12
			$0.caughtAt = F.date("2026-11-27T01:00:00Z")
		}
		let (entries, reloadAt) = WidgetContent.timeline(snapshot: snapshot, signedIn: true, now: F.chase.asOf, calendar: F.newYork)
		#expect(entries.count == 9)
		#expect(entries.last?.date == F.date("2026-11-27T01:00:00Z"))
		#expect(reloadAt == F.date("2026-11-27T01:00:00Z"))
		let shown = chases(entries)
		#expect(shown.last?.lead == 0)
		#expect(shown.allSatisfy { $0.state == .running && $0.headline != "Got you" })
		#expect(shown.last?.headline == "0 steps")
	}

	@Test func entriesStopAtTheNextDayWhenItComesFirst() {
		let snapshot = F.snapshot { $0.nextDayStartsAt = F.date("2026-11-27T00:30:00Z") }
		let (entries, reloadAt) = WidgetContent.timeline(snapshot: snapshot, signedIn: true, now: F.chase.asOf, calendar: F.newYork)
		#expect(entries.map(\.date).last == F.date("2026-11-27T00:30:00Z"))
		#expect(entries.count == 7)
		#expect(reloadAt == F.date("2026-11-27T00:30:00Z"))
	}

	@Test func aCaughtDaySaysSoUntilTheNextDay() throws {
		let snapshot = F.snapshot(receivedAt: F.date("2026-11-27T02:45:00Z")) {
			$0.state = .caught
			$0.lead = 0
			$0.asOf = F.date("2026-11-27T02:45:00Z")
			$0.caughtAt = F.date("2026-11-27T02:41:00Z")
		}
		let (entries, reloadAt) = WidgetContent.timeline(snapshot: snapshot, signedIn: true, now: F.date("2026-11-27T02:45:00Z"), calendar: F.newYork)
		#expect(entries.count == 1)
		#expect(reloadAt == F.date("2026-11-27T11:00:00Z"))
		let shown = try #require(chases(entries).first)
		#expect(shown.headline == "Got you")
		// The formatter puts a narrow no-break space before PM.
		#expect(shown.subline.replacingOccurrences(of: "\u{202F}", with: " ") == "at 9:41 PM")
	}

	@Test func anOutOfDateChaseIsDrawnWithItsAgeAndFetchedAgainSoon() throws {
		let now = F.chase.asOf + 2 * 3600 + 60
		let (entries, reloadAt) = WidgetContent.timeline(snapshot: F.snapshot(isOutOfDate: true), signedIn: true, now: now, calendar: F.newYork)
		#expect(entries.count == 1)
		#expect(reloadAt == now + 15 * 60)
		#expect(try #require(chases(entries).first).subline == "Updated 2 hr ago")
	}

	@Test func aChasePastItsEndIsDrawnWithItsAge() throws {
		let now = F.date("2026-11-27T12:00:00Z")
		let (entries, _) = WidgetContent.timeline(snapshot: F.snapshot(), signedIn: true, now: now, calendar: F.newYork)
		#expect(try #require(chases(entries).first).age == "13 hr")
	}

	@Test func signedOutAndNoChaseOpenTheApp() {
		#expect(WidgetContent.timeline(snapshot: F.snapshot(), signedIn: false, now: .now).entries.map(\.shown) == [.signedOut])
		#expect(WidgetContent.timeline(snapshot: nil, signedIn: true, now: .now).entries.map(\.shown) == [.noChase])
	}
}
