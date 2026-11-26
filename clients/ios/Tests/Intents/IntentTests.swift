import Foundation
import GooseCore
import Testing
@testable import FeedTheGoose

/// Records what the intents send, over the fixture services, and can play an unreachable or
/// settled server.
actor RecordingLogs: LogService {
	let base: FixtureServices
	private(set) var sent: [LogRequest] = []
	private var failure: APIError?

	init(base: FixtureServices) { self.base = base }

	func fail(with error: APIError?) { failure = error }

	func createLog(_ request: LogRequest) async throws -> LogResult {
		sent.append(request)
		if let failure { throw failure }
		return try await base.createLog(request)
	}

	func undoLog(id: UUID) async throws -> LogResult {
		if let failure { throw failure }
		return try await base.undoLog(id: id)
	}

	func logs(on date: LocalDate) async throws -> [LogEntry] { try await base.logs(on: date) }
}

/// Fails every fetch of the chase.
struct UnreachableChase: ChaseService {
	func today() async throws -> Chase { throw APIError.transport("offline") }
	func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { throw APIError.transport("offline") }
}

@MainActor
struct IntentTests {
	let pushups = HabitEntity(id: UUID(uuidString: "22222222-2222-4222-8222-000000000001")!, name: "Pushups", unit: "reps", chunk: 10)
	let fixtures = FixtureServices()
	let logs: RecordingLogs
	let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "intents-\(UUID().uuidString)"))

	init() {
		logs = RecordingLogs(base: fixtures)
		shared.setChaseSnapshot(ChaseSnapshot(chase: try! Fixtures.load("example-day-07-chase").response(), receivedAt: Date()))
		shared.setHabits(try! Fixtures.load("habits-list").response())
	}

	func environment(token: String? = "token", chase: (any ChaseService)? = nil) -> AppEnvironment {
		AppEnvironment(
			auth: fixtures, account: fixtures, habits: fixtures, logs: logs, chase: chase ?? fixtures,
			session: .inMemory(token: token), shared: shared
		)
	}

	@Test func logHabitRepliesWithTheNewLeadAndComesFromShortcuts() async throws {
		let reply = await LogHabitIntent(habit: pushups).perform(in: environment())
		// 10 of 50 reps of one of three habits: 6.7 steps on a lead of 80.
		#expect(reply == "Logged 10 reps of Pushups. The goose is 87 steps behind you.")
		let sent = try #require(await logs.sent.first)
		#expect(sent.source == .shortcuts)
		#expect(sent.amount == nil)
		#expect(shared.chaseSnapshot?.chase.lead == 86.7)
	}

	@Test func anAmountIsSentAsGiven() async throws {
		let reply = await LogHabitIntent(habit: pushups, amount: 30).perform(in: environment())
		#expect(reply == "Logged 30 reps of Pushups. The goose is 100 steps behind you.")
		#expect(await logs.sent.first?.amount == 30)
	}

	@Test func aWidgetButtonLogsItsChunkWithTheWidgetSource() async throws {
		_ = await LogFromWidgetIntent(habitID: pushups.id, amount: 10).perform(in: environment())
		let sent = try #require(await logs.sent.first)
		#expect(sent.source == .widget)
		#expect(sent.amount == 10)
		#expect(sent.habitID == pushups.id)
	}

	@Test func anUnreachableServerQueuesTheLog() async {
		await logs.fail(with: .transport("offline"))
		let environment = environment()
		let reply = await LogHabitIntent(habit: pushups).perform(in: environment)
		#expect(reply == "Saved. Pushups will count when your phone is back online.")
		#expect(environment.logQueue.pending().map(\.source) == [.shortcuts])
		#expect(shared.chaseSnapshot?.chase.lead == 80)
	}

	@Test func aSettledDayIsTooLate() async {
		await logs.fail(with: .daySettled)
		let environment = environment()
		let reply = await LogHabitIntent(habit: pushups).perform(in: environment)
		#expect(reply == "That day has ended, so the log was too late to count.")
		#expect(environment.logQueue.pending().isEmpty)
	}

	@Test func signedOutSendsNothing() async {
		let reply = await LogHabitIntent(habit: pushups).perform(in: environment(token: nil))
		#expect(reply == "Open Feed the Goose and sign in first.")
		#expect(await logs.sent.isEmpty)
	}

	@Test func undoUndoesTheNewestLog() async {
		let environment = environment()
		_ = await LogHabitIntent(habit: pushups).perform(in: environment)
		let reply = await UndoLastLogIntent().perform(in: environment)
		#expect(reply == "Undid 10 reps of Pushups. The goose is 80 steps behind you.")
		#expect(shared.chaseSnapshot?.chase.lead == 80)
	}

	@Test func getChaseSaysTheStateAndTheLead() async {
		#expect(await GetChaseIntent().perform(in: environment()) == "The goose is 80 steps behind you.")
	}

	@Test func getChaseGivesTheAgeOfAChaseItCouldNotFetch() async {
		let reply = await GetChaseIntent().perform(in: environment(chase: UnreachableChase()))
		#expect(reply == "The goose is 80 steps behind you. That was less than a minute ago; Feed the Goose couldn't be reached since.")
	}

	@Test func habitEntitiesComeFromTheCache() {
		#expect(HabitEntity.all(in: environment()).map(\.name) == ["Pushups", "Workout", "Reading"])
	}
}
