import Foundation

/// What became of a log the queue sent.
public enum LogOutcome: Hashable, Sendable {
	/// The server counted it. `clip` is what the event deserves.
	case logged(LogRequest, LogResult, clip: Clip?)
	/// Not sent, or no answer: it stays queued and counts when the phone is back online.
	case queued(LogRequest)
	/// Its day had settled, so it was dropped. The user is told it was too late.
	case tooLate(LogRequest)
	/// The server refused it (an unknown habit or an invalid amount), so it was dropped.
	/// Retrying cannot help.
	case rejected(LogRequest, APIError)
	/// It could not be written to the queue and did not reach the server, so nothing will retry
	/// it. The user must be told it was not logged.
	case notSaved(LogRequest)

	public var request: LogRequest {
		switch self {
		case let .logged(request, _, _), let .queued(request), let .tooLate(request), let .rejected(request, _),
		     let .notSaved(request):
			request
		}
	}
}

/// The retry queue (TDD §6.6, constitution §3). Each queued log is one file in the App Group's
/// `queue/` directory, named by its ID and written atomically; removing a log deletes its file.
/// The app, the widget extension and the intents can therefore share the queue without a lock:
/// at worst two of them send the same log, and the server treats a repeated ID as the same log.
public struct LogQueue: Sendable {
	public let directory: URL
	private let service: any LogService
	private let chaseStore: ChaseStore
	private let timeout: Duration
	private let now: @Sendable () -> Date

	public init(
		directory: URL,
		service: any LogService,
		chaseStore: ChaseStore,
		timeout: Duration = .seconds(5),
		now: @escaping @Sendable () -> Date = Date.init
	) {
		self.directory = directory
		self.service = service
		self.chaseStore = chaseStore
		self.timeout = timeout
		self.now = now
	}

	/// Logs `amount` of a habit, or its chunk when nil. The ID and `loggedAt` are made now, once,
	/// and the log is on disk before it is sent. Older queued logs are sent first, so the server
	/// receives logs in `loggedAt` order.
	public func log(habitID: UUID, amount: Int?, source: LogSource) async -> LogOutcome {
		let at = now()
		// The API's timestamps are to the second, so the stored value is the one that is sent.
		let loggedAt = Date(timeIntervalSince1970: at.timeIntervalSince1970.rounded(.down))
		let request = LogRequest(id: .v7(at: at), habitID: habitID, amount: amount, loggedAt: loggedAt, source: source)
		guard (try? write(request)) != nil else {
			let outcome = await send(request)
			if case .queued = outcome { return .notSaved(request) }
			return outcome
		}
		let outcomes = await drain()
		if let outcome = outcomes.first(where: { $0.request.id == request.id }) { return outcome }
		// Another process sent it first. Sending it again returns the same log.
		if !FileManager.default.fileExists(atPath: fileURL(request.id).path) { return await send(request) }
		return .queued(request)
	}

	/// The logs waiting to be sent, oldest `loggedAt` first.
	public func pending() -> [LogRequest] {
		let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
		return files
			.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
			.compactMap { try? WireJSON.decoder().decode(LogRequest.self, from: Data(contentsOf: $0)) }
			.sorted { ($0.loggedAt, $0.id.uuidString) < ($1.loggedAt, $1.id.uuidString) }
	}

	/// Sends every queued log in `loggedAt` order. Stops at the first log that stays queued,
	/// because the rest would most likely fail the same way.
	@discardableResult
	public func drain() async -> [LogOutcome] {
		var outcomes: [LogOutcome] = []
		for request in pending() {
			let outcome = await send(request)
			outcomes.append(outcome)
			if case .queued = outcome { break }
		}
		return outcomes
	}

	private func send(_ request: LogRequest) async -> LogOutcome {
		do {
			let result = try await withTimeout { try await service.createLog(request) }
			let clip = await chaseStore.receive(result)
			remove(request)
			return .logged(request, result, clip: clip)
		} catch APIError.daySettled {
			remove(request)
			return .tooLate(request)
		} catch let error as APIError {
			switch error {
			case .notFound, .invalid:
				remove(request)
				return .rejected(request, error)
			default:
				return .queued(request)
			}
		} catch {
			return .queued(request)
		}
	}

	private func fileURL(_ id: UUID) -> URL {
		directory.appending(path: "\(id.uuidString.lowercased()).json")
	}

	private func write(_ request: LogRequest) throws {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try WireJSON.encoder().encode(request).write(to: fileURL(request.id), options: .atomic)
	}

	private func remove(_ request: LogRequest) {
		// Another process may have removed it already.
		try? FileManager.default.removeItem(at: fileURL(request.id))
	}

	private struct TimedOut: Error {}

	private func withTimeout<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
		try await withThrowingTaskGroup(of: Value.self) { group in
			group.addTask { try await operation() }
			group.addTask { [timeout] in
				try await Task.sleep(for: timeout)
				throw TimedOut()
			}
			defer { group.cancelAll() }
			guard let value = try await group.next() else { throw TimedOut() }
			return value
		}
	}
}
