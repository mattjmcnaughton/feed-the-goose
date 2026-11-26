import Foundation
import GooseCore
import Testing

/// The example chase (`example-day-07-chase`): running, lead 80.0 at 23:00Z, 5.56 steps an
/// hour, the day ending at 05:00Z, six hours later. The device clock is five minutes fast, so it
/// receives the chase at what it thinks is 23:05Z. Expected leads are worked out by hand.
struct ChaseClockTests {
	static let deviceSkew: TimeInterval = 5 * 60

	struct Case: Sendable, CustomStringConvertible {
		let description: String
		let lead: Double
		let state: ChaseState
		/// Hours of device time since the chase arrived.
		let hours: Double
		let expected: Double
	}

	static let cases: [Case] = [
		Case(description: "at receipt", lead: 80, state: .running, hours: 0, expected: 80),
		// Measured from receipt, not from as_of: a fast clock would otherwise take 65 minutes (73.98).
		Case(description: "one hour on a fast clock", lead: 80, state: .running, hours: 1, expected: 74.44),
		Case(description: "exactly at day_ends_at", lead: 80, state: .running, hours: 6, expected: 46.64),
		Case(description: "stops at day_ends_at", lead: 80, state: .running, hours: 9, expected: 46.64),
		Case(description: "a low lead after one hour", lead: 10, state: .running, hours: 1, expected: 4.44),
		Case(description: "never below 0", lead: 10, state: .running, hours: 2, expected: 0),
		Case(description: "a complete day does not move", lead: 80, state: .complete, hours: 3, expected: 80),
		Case(description: "a device time before receipt", lead: 80, state: .running, hours: -1, expected: 80),
	]

	@Test(arguments: cases)
	func lead(_ example: Case) throws {
		var chase = try Fixtures.load("example-day-07-chase").response(as: Chase.self)
		chase.lead = example.lead
		chase.state = example.state
		let receivedAt = chase.asOf.addingTimeInterval(Self.deviceSkew)
		let clock = ChaseClock(chase: chase, receivedAt: receivedAt)
		let lead = clock.lead(at: receivedAt.addingTimeInterval(example.hours * 3600))
		#expect(abs(lead - example.expected) < 1e-9, "\(example): \(lead)")
	}

	@Test func serverTimesMapToTheDeviceClock() throws {
		let chase = try Fixtures.load("example-day-07-chase").response(as: Chase.self)
		let receivedAt = chase.asOf.addingTimeInterval(Self.deviceSkew)
		let clock = ChaseClock(chase: chase, receivedAt: receivedAt)
		#expect(clock.deviceTime(of: chase.dayEndsAt) == receivedAt.addingTimeInterval(6 * 3600))
	}
}
