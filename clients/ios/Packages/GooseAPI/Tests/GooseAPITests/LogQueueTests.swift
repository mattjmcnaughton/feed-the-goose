import Foundation
import GooseAPI
import GooseCore
import Testing

/// A stand-in for the server's log routes: it stores each log once by ID, answers 201 for a new
/// ID and 200 for a repeat, and can be offline, slow, or past the day's settlement.
final class LogServer: @unchecked Sendable {
	enum Mode { case online, offline, slow, settled, unknownHabit, invalid, signedOut, bareServerError }

	private let lock = NSLock()
	private var _mode: Mode = .online
	private var _stored: [String: [String: Any]] = [:]
	private let template = try! Fixtures.load("example-day-01-log-pushups").responseBody!

	/// The transport the live services send through. It holds this server strongly; tests are
	/// short-lived, so the cycle does not matter.
	var stub: StubServer {
		lock.withLock {
			if let _stub { return _stub }
			let stub = StubServer { [self] request in try await answer(request) }
			_stub = stub
			return stub
		}
	}

	private var _stub: StubServer?

	var mode: Mode {
		get { lock.withLock { _mode } }
		set { lock.withLock { _mode = newValue } }
	}

	/// The logs the server holds, by ID, as their request bodies.
	var stored: [String: [String: Any]] { lock.withLock { _stored } }

	private func problem(_ type: String, _ status: Int) -> (Int, Data?) {
		(status, Data(#"{"type":"\#(type)","title":"t","status":\#(status)}"#.utf8))
	}

	private func answer(_ request: RecordedRequest) async throws -> (status: Int, body: Data?) {
		switch mode {
		case .offline: throw URLError(.notConnectedToInternet)
		case .slow: try await Task.sleep(for: .seconds(5))
		case .settled: return problem("day_settled", 409)
		case .unknownHabit: return problem("not_found", 404)
		case .invalid: return problem("invalid", 422)
		case .signedOut: return problem("unauthenticated", 401)
		case .bareServerError: return (502, Data("Bad Gateway".utf8))
		case .online: break
		}
		let body = try #require(request.json)
		let id = try #require(body["id"] as? String)
		let isNew = lock.withLock {
			guard _stored[id] == nil else { return false }
			_stored[id] = body
			return true
		}
		var result = try #require(try JSONSerialization.jsonObject(with: template) as? [String: Any])
		var log = try #require(result["log"] as? [String: Any])
		log["id"] = id
		log["habit_id"] = body["habit_id"]
		log["logged_at"] = body["logged_at"]
		log["source"] = body["source"]
		result["log"] = log
		return (isNew ? 201 : 200, try JSONSerialization.data(withJSONObject: result))
	}
}

/// A device clock the test moves.
final class TestClock: @unchecked Sendable {
	private let lock = NSLock()
	private var _now: Date
	init(_ iso: String) { _now = try! Date(iso, strategy: .iso8601) }
	var now: Date {
		get { lock.withLock { _now } }
		set { lock.withLock { _now = newValue } }
	}
}

struct LogQueueTests {
	let directory = FileManager.default.temporaryDirectory.appending(path: "log-queue-\(UUID().uuidString)")
	let server = LogServer()
	/// 14:05:00.700 UTC: the log's time is sent to the second, as 14:05:00Z.
	let clock = TestClock("2026-11-26T14:05:00Z")
	let pushups = UUID(uuidString: "22222222-2222-4222-8222-000000000001")!

	init() { clock.now = clock.now.addingTimeInterval(0.7) }

	func makeQueue(timeout: Duration = .seconds(5)) -> LogQueue {
		let services = server.stub.services()
		let shared = SharedStore(directory: directory)
		let store = ChaseStore(service: services, shared: shared)
		return LogQueue(directory: directory.appending(path: "queue"), service: services, chaseStore: store, timeout: timeout, now: { [clock] in clock.now })
	}

	func files(_ queue: LogQueue) -> [String] {
		((try? FileManager.default.contentsOfDirectory(atPath: queue.directory.path)) ?? []).filter { $0.hasSuffix(".json") }
	}

	@Test func successRemovesTheFile() async throws {
		let queue = makeQueue()
		let outcome = await queue.log(habitID: pushups, amount: 10, source: .app)
		guard case let .logged(request, result, clip) = outcome else { Issue.record("got \(outcome)"); return }
		#expect(result.log.id == request.id)
		#expect(clip == .snap)
		#expect(files(queue).isEmpty)
		#expect(server.stored.count == 1)
	}

	@Test func aTimeoutKeepsTheFile() async throws {
		server.mode = .slow
		let queue = makeQueue(timeout: .milliseconds(300))
		let started = ContinuousClock.now
		let outcome = await queue.log(habitID: pushups, amount: 10, source: .widget)
		#expect(ContinuousClock.now - started < .seconds(3))
		guard case let .queued(request) = outcome else { Issue.record("got \(outcome)"); return }
		#expect(files(queue) == ["\(request.id.uuidString.lowercased()).json"])
		#expect(queue.pending() == [request])
	}

	@Test func daySettledRemovesTheFileAndReports() async throws {
		server.mode = .settled
		let queue = makeQueue()
		let outcome = await queue.log(habitID: pushups, amount: 10, source: .app)
		guard case .tooLate = outcome else { Issue.record("got \(outcome)"); return }
		#expect(files(queue).isEmpty)
	}

	@Test func anUnknownHabitIsDroppedBecauseRetryingCannotHelp() async throws {
		server.mode = .unknownHabit
		let queue = makeQueue()
		let outcome = await queue.log(habitID: UUID(), amount: 10, source: .app)
		guard case .rejected(_, .notFound) = outcome else { Issue.record("got \(outcome)"); return }
		#expect(files(queue).isEmpty)
	}

	@Test func aRetrySendsTheOriginalIDAndLoggedAt() async throws {
		server.mode = .offline
		let queue = makeQueue()
		guard case let .queued(original) = await queue.log(habitID: pushups, amount: 10, source: .app) else {
			Issue.record("expected the log to queue"); return
		}

		// Three hours later the phone is back online.
		clock.now = clock.now.addingTimeInterval(3 * 3600)
		server.mode = .online
		let outcomes = await queue.drain()
		#expect(outcomes.count == 1)
		#expect(files(queue).isEmpty)

		let sent = server.stub.requests
		#expect(sent.count == 2)
		for request in sent {
			#expect(request.json?["id"] as? String == original.id.uuidString.lowercased())
			#expect(request.json?["logged_at"] as? String == "2026-11-26T14:05:00Z")
			#expect(request.json?["amount"] as? Int == 10)
		}
	}

	@Test func twoQueuesOverOneDirectoryNeitherLoseNorDuplicateALog() async throws {
		server.mode = .offline
		let first = makeQueue()
		var queued: Set<String> = []
		for index in 0 ..< 20 {
			clock.now = clock.now.addingTimeInterval(60)
			let outcome = await first.log(habitID: pushups, amount: index + 1, source: .app)
			queued.insert(outcome.request.id.uuidString.lowercased())
		}
		#expect(files(first).count == 20)

		// The app and the widget extension drain the same directory at once.
		server.mode = .online
		let second = makeQueue()
		async let a = first.drain()
		async let b = second.drain()
		_ = await (a, b)

		#expect(files(first).isEmpty)
		#expect(Set(server.stored.keys) == queued)
		#expect(server.stored.count == 20)
		// Each stored log kept the amount it was made with.
		let amounts = Set(server.stored.values.compactMap { $0["amount"] as? Int })
		#expect(amounts == Set(1 ... 20))
	}

	@Test(arguments: [
		(LogServer.Mode.bareServerError, true), (.signedOut, true), (.offline, true),
		(.invalid, false), (.unknownHabit, false), (.settled, false),
	])
	func onlyAnAnswerThatRetryingCannotChangeDropsTheLog(mode: LogServer.Mode, kept: Bool) async {
		server.mode = mode
		let queue = makeQueue()
		let outcome = await queue.log(habitID: pushups, amount: 10, source: .app)
		#expect(files(queue).count == (kept ? 1 : 0), "\(mode): \(outcome)")
		if kept {
			guard case .queued = outcome else { Issue.record("\(mode): \(outcome)"); return }
		}
	}

	@Test func aLogThatCannotBeWrittenAndIsNotSentIsNotReportedAsQueued() async throws {
		server.mode = .offline
		// A file where the queue's directory should be makes every write fail.
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		FileManager.default.createFile(atPath: directory.appending(path: "queue").path, contents: Data())
		let outcome = await makeQueue().log(habitID: pushups, amount: 10, source: .app)
		guard case .notSaved = outcome else { Issue.record("got \(outcome)"); return }
	}

	@Test func aNewLogIsSentAfterTheLogsAlreadyQueued() async {
		server.mode = .offline
		let queue = makeQueue()
		let first = await queue.log(habitID: pushups, amount: 1, source: .app).request
		clock.now = clock.now.addingTimeInterval(60)
		server.mode = .online
		let second = await queue.log(habitID: pushups, amount: 2, source: .app)
		guard case .logged = second else { Issue.record("got \(second)"); return }
		let ids = server.stub.requests.compactMap { $0.json?["id"] as? String }
		#expect(ids.last == second.request.id.uuidString.lowercased())
		#expect(ids.dropLast().last == first.id.uuidString.lowercased())
		#expect(files(queue).isEmpty)
	}

	@Test func loggingWhileAnotherProcessDrainsLosesNothing() async {
		server.mode = .offline
		let app = makeQueue()
		var made: Set<String> = []
		for index in 0 ..< 10 {
			clock.now = clock.now.addingTimeInterval(60)
			made.insert(await app.log(habitID: pushups, amount: index + 1, source: .app).request.id.uuidString.lowercased())
		}
		server.mode = .online
		let widget = makeQueue()
		async let drained = widget.drain()
		for index in 10 ..< 20 {
			made.insert(await app.log(habitID: pushups, amount: index + 1, source: .widget).request.id.uuidString.lowercased())
		}
		_ = await drained
		await app.drain()
		#expect(files(app).isEmpty)
		#expect(Set(server.stored.keys) == made)
		#expect(server.stored.count == 20)
	}
}
