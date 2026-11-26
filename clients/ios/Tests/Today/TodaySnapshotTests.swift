import Foundation
import GooseCore
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import FeedTheGoose

/// A server that never answers, so a snapshot shows exactly the chase the test cached.
struct SilentServer: LogService, ChaseService {
	func today() async throws -> Chase {
		try await Task.sleep(for: .seconds(3600))
		throw APIError.transport("silent")
	}
	func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { [] }
	func createLog(_ request: LogRequest) async throws -> LogResult { throw APIError.transport("silent") }
	func undoLog(id: UUID) async throws -> LogResult { throw APIError.transport("silent") }
	func logs(on date: LocalDate) async throws -> [LogEntry] { [] }
}

/// Today in the eight states of TDD §7, at the default type size and at accessibility medium.
/// The references are recorded on the pinned simulator; open them before reporting.
@MainActor
struct TodaySnapshotTests {
	static let newYork = TimeZone(identifier: "America/New_York")!

	static func config(large: Bool) -> ViewImageConfig {
		ViewImageConfig(
			safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
			// The iPhone 17 Pro's screen. The large size is taller so the whole screen shows.
			size: CGSize(width: 402, height: large ? 1500 : 874),
			traits: UITraitCollection(traitsFrom: [
				UITraitCollection(displayScale: 3),
				UITraitCollection(userInterfaceStyle: .light),
				UITraitCollection(userInterfaceIdiom: .phone),
				UITraitCollection(preferredContentSizeCategory: large ? .accessibilityMedium : .large),
			])
		)
	}

	/// The example day at 18:00 New York: running, lead 80, Pushups 20 of 50, Workout done,
	/// Reading 0 of 20, a 13-day streak (a big goose).
	let base: Chase

	init() throws {
		base = try Fixtures.load("example-day-07-chase").response()
	}

	func at(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

	func snapshot(
		_ chase: Chase, named name: String, now: Date? = nil, outOfDate: Bool = false,
		line: TodayModel.Line? = nil, undoable: Bool = false, queued: [LogRequest] = []
	) throws {
		let now = now ?? chase.asOf
		for large in [false, true] {
			let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "today-snap-\(UUID().uuidString)"))
			shared.setChaseSnapshot(ChaseSnapshot(chase: chase, receivedAt: chase.asOf, isOutOfDate: outOfDate))
			try FileManager.default.createDirectory(at: shared.queueDirectory, withIntermediateDirectories: true)
			for request in queued {
				try WireJSON.encoder().encode(request).write(to: shared.queueDirectory.appending(path: "\(request.id.uuidString.lowercased()).json"))
			}
			let fixtures = FixtureServices()
			let environment = AppEnvironment(
				auth: fixtures, account: fixtures, habits: fixtures, logs: SilentServer(), chase: SilentServer(),
				session: .inMemory(), shared: shared, now: { now }
			)
			let model = TodayModel(environment: environment, now: { now }, timeZone: Self.newYork)
			model.line = line
			model.undoable = undoable ? UUID() : nil
			let controller = UIHostingController(rootView: TodayView(model: model))
			assertSnapshot(
				of: controller, as: .image(on: Self.config(large: large), precision: 0.99),
				named: "\(name)\(large ? ".large" : "")", testName: "today"
			)
		}
	}

	@Test func morningWithNothingLogged() throws {
		var chase = base
		chase.asOf = at("2026-11-26T13:00:00Z")
		chase.earned = 0
		chase.walked = 11.1
		chase.lead = 88.9
		for i in chase.habits.indices {
			chase.habits[i].logged = 0
			chase.habits[i].steps = 0
			chase.habits[i].done = false
		}
		try snapshot(chase, named: "morning")
	}

	/// Compare with docs/prototypes/screenshots/04-app-screens/today-part-fed.png.
	@Test func partLogged() throws {
		try snapshot(base, named: "part-logged", line: .logged(amount: 10, unit: "reps", steps: 6.7, kind: .gain), undoable: true)
	}

	@Test func lowLead() throws {
		var chase = base
		chase.asOf = at("2026-11-27T03:00:00Z")
		chase.walked = 88.9
		chase.lead = 12.0
		try snapshot(chase, named: "low-lead")
	}

	@Test func complete() throws {
		var chase = base
		chase.state = .complete
		chase.asOf = at("2026-11-26T23:00:00Z")
		chase.lead = 155.6
		chase.earned = 100
		for i in chase.habits.indices {
			chase.habits[i].logged = chase.habits[i].target
			chase.habits[i].steps = 33.3
			chase.habits[i].done = true
		}
		chase.streak = Streak(completeDays: 14, stage: 3)
		try snapshot(chase, named: "complete")
	}

	/// The example table's case 10 at 00:30: Pushups 50 only, short with 33.3 to spare.
	@Test func shortAtNight() throws {
		var chase = base
		chase.state = .short
		chase.asOf = at("2026-11-27T05:30:00Z")
		chase.lead = 33.3
		chase.earned = 33.3
		chase.walked = 100
		chase.habits[0].logged = 50
		chase.habits[0].steps = 33.3
		chase.habits[0].done = true
		chase.habits[1].logged = 0
		chase.habits[1].steps = 0
		chase.habits[1].done = false
		try snapshot(chase, named: "short-at-night")
	}

	/// The example table's case 6: a starting lead of 20 and no logs, caught at 09:36.
	@Test func caught() throws {
		var chase = base
		chase.state = .caught
		chase.asOf = at("2026-11-26T17:00:00Z")
		chase.startingLead = 20
		chase.lead = 0
		chase.earned = 0
		chase.walked = 20
		chase.caughtAt = at("2026-11-26T14:36:00Z")
		for i in chase.habits.indices {
			chase.habits[i].logged = 0
			chase.habits[i].steps = 0
			chase.habits[i].done = false
		}
		chase.streak = Streak(completeDays: 0, stage: 0)
		try snapshot(chase, named: "caught")
	}

	@Test func queuedWhileOffline() throws {
		let request = LogRequest(
			id: UUID(uuidString: "01a218f0-0000-7000-8000-000000000001")!, habitID: base.habits[2].habitID,
			amount: 5, loggedAt: at("2026-11-26T22:58:00Z"), source: .app
		)
		try snapshot(base, named: "queued", outOfDate: true, line: .queued(amount: 5, unit: "pages"), queued: [request])
	}

	@Test func outOfDate() throws {
		try snapshot(base, named: "out-of-date", now: base.asOf.addingTimeInterval(12 * 60), outOfDate: true)
	}
}
