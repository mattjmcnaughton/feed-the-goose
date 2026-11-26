import Foundation
import GooseCore
import Synchronization
import Testing
@testable import FeedTheGoose

/// A device clock the test moves by hand.
final class TestClock: Sendable {
	private let value: Mutex<Date>
	init(_ date: Date) { value = Mutex(date) }
	var now: Date { value.withLock { $0 } }
	func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
	var read: @Sendable () -> Date { { self.now } }
}

/// A server for Today's two questions, the chase and logs, that answers what the test says.
actor FakeTodayServer: LogService, ChaseService {
	var chaseResult: Result<Chase, APIError>
	var logResult: Result<LogResult, APIError>
	private(set) var sent: [LogRequest] = []

	init(chase: Result<Chase, APIError>, log: Result<LogResult, APIError> = .failure(.transport("offline"))) {
		chaseResult = chase
		logResult = log
	}

	func setChase(_ result: Result<Chase, APIError>) { chaseResult = result }
	func setLog(_ result: Result<LogResult, APIError>) { logResult = result }

	func today() async throws -> Chase { try chaseResult.get() }
	func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { [] }
	func createLog(_ request: LogRequest) async throws -> LogResult {
		sent.append(request)
		return try logResult.get()
	}
	func undoLog(id: UUID) async throws -> LogResult { try logResult.get() }
	func logs(on date: LocalDate) async throws -> [LogEntry] { [] }
}

@MainActor
struct TodayModelTests {
	let chase: Chase
	let clock: TestClock
	let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "today-model-\(UUID().uuidString)"))

	init() throws {
		// The example day at 18:00 New York: running, lead 80.0, 5.56 steps an hour, the day
		// ending at 00:00 (05:00Z).
		chase = try Fixtures.load("example-day-07-chase").response()
		clock = TestClock(chase.asOf)
	}

	func model(_ server: FakeTodayServer) -> TodayModel {
		let fixtures = FixtureServices()
		let environment = AppEnvironment(
			auth: fixtures, account: fixtures, habits: fixtures, logs: server, chase: server,
			session: .inMemory(), shared: shared, now: clock.read
		)
		return TodayModel(environment: environment, now: clock.read, timeZone: TimeZone(identifier: "America/New_York")!)
	}

	@Test func theLeadCountsDownBetweenFetchesAndStopsAtTheDayEnd() async {
		let today = model(FakeTodayServer(chase: .success(chase)))
		await today.refresh()
		#expect(today.lead(at: clock.now) == 80.0)
		// Half an hour at 5.56 steps an hour is 2.78 steps.
		#expect(abs(today.lead(at: clock.now.addingTimeInterval(1800))! - 77.22) < 0.001)
		// At 00:00, six hours on, the goose has walked 33.36 and stops.
		let atEnd = 80.0 - 5.56 * 6
		#expect(abs(today.lead(at: clock.now.addingTimeInterval(6 * 3600))! - atEnd) < 0.001)
		#expect(abs(today.lead(at: clock.now.addingTimeInterval(9 * 3600))! - atEnd) < 0.001)
	}

	@Test func aFailedFetchKeepsTheChaseMarkedOutOfDate() async throws {
		let server = FakeTodayServer(chase: .success(chase))
		let today = model(server)
		await today.refresh()
		clock.advance(12 * 60)
		await server.setChase(.failure(.transport("offline")))
		await today.refresh()
		guard case let .showing(snapshot) = today.state else {
			Issue.record("Expected the old chase on screen, got \(today.state)")
			return
		}
		#expect(snapshot.isOutOfDate)
		#expect(snapshot.chase.lead == 80.0)
		#expect(TodayText.outOfDate(snapshot, at: clock.now) == "Out of date: last updated 12 min ago. Pull to refresh.")
	}

	@Test func aQueuedLogIsListedAndNotCounted() async throws {
		let today = model(FakeTodayServer(chase: .success(chase)))
		await today.refresh()
		let pushups = chase.habits[0]
		await today.log(pushups, amount: 10)

		#expect(today.pending.map(\.habitID) == [pushups.habitID])
		#expect(today.pending.first?.amount == 10)
		#expect(today.line == .queued(amount: 10, unit: "reps"))
		#expect(today.undoable == nil)
		#expect(today.playing == nil)
		// The chase is the server's: the lead and the habit's progress have not moved.
		#expect(today.snapshot?.chase.lead == 80.0)
		#expect(today.snapshot?.chase.habits[0].logged == 20)
		let readout = TodayText.readout(today.snapshot!, at: clock.now, line: today.line, timeZone: today.timeZone)
		#expect(readout.head == "80 steps behind you")
		#expect(readout.sub == "10 reps logged, they'll count when you're back online.")
	}

	@Test func aQueuedLogIsSentOnRefreshAndCountsOnce() async throws {
		let server = FakeTodayServer(chase: .success(chase))
		let today = model(server)
		await today.refresh()
		await today.log(chase.habits[0], amount: 10)
		let queued = try #require(today.pending.first)

		var after = chase
		after.lead = 86.7
		after.habits[0].logged = 30
		after.asOf = chase.asOf.addingTimeInterval(60)
		let log = LogEntry(id: queued.id, habitID: queued.habitID, amount: 10, loggedAt: queued.loggedAt, source: .app, date: chase.date, steps: 6.7, undoneAt: nil)
		await server.setLog(.success(LogResult(log: log, event: ChaseEvent(kind: .gain, habitID: queued.habitID, steps: 6.7), chase: after)))
		await server.setChase(.success(after))
		await today.refresh()

		#expect(today.pending.isEmpty)
		#expect(today.line == .sent(count: 1))
		#expect(today.snapshot?.chase.habits[0].logged == 30)
		// The retry carries the ID and time made when the user tapped.
		let sent = await server.sent
		#expect(sent.last?.id == queued.id)
		#expect(sent.last?.loggedAt == queued.loggedAt)
	}

	@Test func aLogForASettledDayIsTooLate() async {
		let today = model(FakeTodayServer(chase: .success(chase), log: .failure(.daySettled)))
		await today.refresh()
		await today.log(chase.habits[2], amount: 5)
		#expect(today.pending.isEmpty)
		#expect(today.line == .tooLate(amount: 5, unit: "pages"))
		#expect(TodayText.text(today.line!) == "5 pages arrived after the day settled, so they didn't count.")
	}

	@Test func aCountedLogPlaysSnapFromTheLeadBeforeIt() async {
		var after = chase
		after.lead = 86.7
		after.asOf = chase.asOf.addingTimeInterval(1)
		let id = UUID()
		let log = LogEntry(id: id, habitID: chase.habits[0].habitID, amount: 10, loggedAt: chase.asOf, source: .app, date: chase.date, steps: 6.7, undoneAt: nil)
		let result = LogResult(log: log, event: ChaseEvent(kind: .gain, habitID: log.habitID, steps: 6.7), chase: after)
		let today = model(FakeTodayServer(chase: .success(chase), log: .success(result)))
		await today.refresh()
		await today.log(chase.habits[0], amount: 10)

		#expect(today.playing?.clip == .snap)
		#expect(today.playing?.fromLead == 80.0)
		#expect(today.undoable == id)
		#expect(today.snapshot?.chase.lead == 86.7)
		#expect(TodayText.text(today.line!) == "10 reps logged. The goose stops for the crust and you gain 7 steps.")
	}

	@Test func aDayCaughtWhileTodayIsOpenPlaysPeckWithTheGooseThatWasChasing() async {
		let server = FakeTodayServer(chase: .success(chase))
		let today = model(server)
		await today.refresh()
		var caught = chase
		caught.state = .caught
		caught.lead = 0
		caught.asOf = chase.asOf.addingTimeInterval(60)
		caught.streak = Streak(completeDays: 0, stage: 0)
		await server.setChase(.success(caught))
		await today.refresh()
		#expect(today.playing?.clip == .peck)
		// The big goose (stage 2) does the catching; the server's new stage is a gosling.
		#expect(today.playing?.stage == 2)
		#expect(today.snapshot?.chase.streak.stage == 0)
		#expect(shared.played(.peck) == chase.date)
	}

	@Test func theNextFetchIsAtTheCatchWhenThatIsSooner() async {
		var close = chase
		close.lead = 0.05
		close.caughtAt = chase.asOf.addingTimeInterval(30)
		let today = model(FakeTodayServer(chase: .success(close)))
		await today.refresh()
		// A second after the catch the server has passed it too; otherwise every 60 seconds.
		#expect(today.nextRefresh(after: clock.now) == clock.now.addingTimeInterval(31))
		#expect(today.nextRefresh(after: clock.now.addingTimeInterval(40)) == clock.now.addingTimeInterval(100))
	}
}
