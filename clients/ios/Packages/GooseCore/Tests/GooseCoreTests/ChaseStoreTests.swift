import Foundation
import GooseCore
import Testing

/// Answers `today()` from a list the test sets.
actor ScriptedChaseService: ChaseService {
	private var answers: [Result<Chase, APIError>] = []

	func answer(_ results: Result<Chase, APIError>...) { answers.append(contentsOf: results) }

	func today() async throws -> Chase {
		try answers.removeFirst().get()
	}

	func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { [] }
}

final class MovingClock: @unchecked Sendable {
	private let lock = NSLock()
	private var value = Date(timeIntervalSince1970: 1_800_000_000)
	var now: Date {
		get { lock.withLock { value } }
		set { lock.withLock { value = newValue } }
	}
}

@MainActor
struct ChaseStoreTests {
	let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "chase-store-\(UUID().uuidString)"))
	let service = ScriptedChaseService()
	let base: Chase
	let logResult: LogResult

	init() throws {
		base = try Fixtures.load("example-day-07-chase").response(as: Chase.self)
		logResult = try Fixtures.load("example-day-01-log-pushups").response(as: LogResult.self)
	}

	func chase(_ state: ChaseState, on date: LocalDate = "2026-11-26") -> Chase {
		var chase = base
		chase.state = state
		chase.date = date
		return chase
	}

	func result(_ kind: ChaseEventKind, _ state: ChaseState, on date: LocalDate = "2026-11-26") -> LogResult {
		var result = logResult
		result.event.kind = kind
		result.chase = chase(state, on: date)
		return result
	}

	@Test func eachEventChoosesItsClip() {
		let store = ChaseStore(service: service, shared: shared)
		#expect(store.receive(result(.gain, .running)) == .snap)
		#expect(store.receive(result(.undone, .running)) == nil)
		#expect(store.receive(result(.complete, .complete)) == .feast)
		#expect(store.receive(result(.caught, .caught)) == .peck)
	}

	@Test func feastAndPeckPlayOncePerDayOnThisDevice() {
		let store = ChaseStore(service: service, shared: shared)
		#expect(store.receive(result(.complete, .complete)) == .feast)
		// A process that cannot show the clip, such as a widget's intent, does not use it up.
		let widget = ChaseStore(service: service, shared: shared)
		#expect(widget.receive(result(.complete, .complete)) == .feast)
		store.markPlayed(.feast, on: "2026-11-26")
		// Undo, then finish the day again: the log still snaps, but Feast does not repeat, in
		// this process or another on the same device.
		#expect(store.receive(result(.complete, .complete)) == .snap)
		#expect(widget.receive(result(.complete, .complete)) == .snap)
		#expect(store.receive(result(.caught, .caught)) == .peck)
		widget.markPlayed(.peck, on: "2026-11-26")
		#expect(store.receive(result(.caught, .caught)) == nil)
		// The next day plays them again.
		#expect(store.receive(result(.complete, .complete, on: "2026-11-27")) == .feast)
	}

	@Test func aRefreshThatChangesTheStateChoosesFeastOrPeckOnce() async {
		let store = ChaseStore(service: service, shared: shared)
		await service.answer(.success(chase(.running)), .success(chase(.complete)), .success(chase(.complete)))
		#expect(await store.refresh() == nil)
		#expect(await store.refresh() == .feast)
		store.markPlayed(.feast, on: "2026-11-26")
		#expect(await store.refresh() == nil)

		await service.answer(.success(chase(.running, on: "2026-11-27")), .success(chase(.caught, on: "2026-11-27")))
		#expect(await store.refresh() == nil)
		#expect(await store.refresh() == .peck)
	}

	@Test func aDayFinishedFromTheWidgetStillPlaysFeastInTheApp() async {
		let app = ChaseStore(service: service, shared: shared)
		await service.answer(.success(chase(.running)), .success(chase(.complete)))
		await app.refresh()
		// The widget's intent finishes the day and caches the complete chase.
		let widget = ChaseStore(service: service, shared: shared)
		_ = widget.receive(result(.complete, .complete))
		#expect(await app.refresh() == .feast)
	}

	@Test func anOlderChaseNeverReplacesTheResultOfALog() async throws {
		var older = chase(.running)
		older.lead = 70
		var newer = result(.gain, .running)
		newer.chase.asOf = older.asOf.addingTimeInterval(60)
		newer.chase.lead = 90

		let store = ChaseStore(service: service, shared: shared)
		store.receive(newer)
		// A fetch answered from before the log.
		await service.answer(.success(older))
		await store.refresh()
		#expect(store.snapshot?.chase.lead == 90)
		#expect(shared.chaseSnapshot?.chase.lead == 90)

		// A fetch that fails keeps the newest chase, marked out of date.
		await service.answer(.failure(.transport("offline")))
		await store.refresh()
		#expect(store.snapshot?.chase.lead == 90)
		#expect(store.snapshot?.isOutOfDate == true)
	}

	@Test func aFailedFetchKeepsTheOldChaseMarkedOutOfDate() async throws {
		let clock = MovingClock()
		let store = ChaseStore(service: service, shared: shared, now: { clock.now })
		await service.answer(.success(chase(.running)), .failure(.transport("offline")))

		await store.refresh()
		let fresh = try #require(store.snapshot)
		#expect(!fresh.isOutOfDate)

		clock.now = clock.now.addingTimeInterval(60)
		await store.refresh()
		let stale = try #require(store.snapshot)
		#expect(stale.isOutOfDate)
		#expect(stale.chase == fresh.chase)
		#expect(stale.receivedAt == fresh.receivedAt, "the age is measured from the last success")
		#expect(store.lastError == .transport("offline"))
		#expect(shared.chaseSnapshot == stale, "the widgets see it as out of date too")
		#expect(store.hasNoChase == false)
	}

	@Test func noChaseClearsTheCachedChase() async {
		let store = ChaseStore(service: service, shared: shared)
		await service.answer(.success(chase(.running)), .failure(.noChase))
		await store.refresh()
		await store.refresh()
		#expect(store.hasNoChase)
		#expect(store.snapshot == nil)
		#expect(shared.chaseSnapshot == nil)
	}
}
