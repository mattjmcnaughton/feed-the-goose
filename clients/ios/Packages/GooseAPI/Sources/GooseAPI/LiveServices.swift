public import Foundation
public import GooseCore
public import OpenAPIRuntime

/// The services over HTTP, through the generated client. Every method throws `APIError`.
public struct LiveServices: AuthService, AccountService, HabitService, LogService, ChaseService {
	private let client: Client

	/// `token` is read on every request; `transport` is the server's unless a test supplies one.
	public init(server: APIServer, token: @escaping @Sendable () throws -> String?, transport: (any ClientTransport)? = nil) {
		client = Client(
			serverURL: server.baseURL,
			transport: transport ?? server.makeTransport(),
			middlewares: [BearerTokenMiddleware(token: token), ProblemMiddleware()]
		)
	}

	/// Runs one generated call and adapts its result, turning any failure into an `APIError`.
	private func call<Value>(_ body: () async throws -> Value) async throws -> Value {
		do {
			return try await body()
		} catch {
			throw APIError(error)
		}
	}

	// MARK: AuthService

	public func createSession(identityToken: String, timeZone: String, deviceName: String) async throws -> NewSession {
		try await call {
			let body = Schemas.SessionCreate(auth0AccessToken: identityToken, deviceName: deviceName, timeZone: timeZone)
			return try await NewSession(client.createSession(body: .json(body)).created.body.json)
		}
	}

	public func sessions() async throws -> [AppSession] {
		try await call { try await client.listSessions().ok.body.json.map(AppSession.init) }
	}

	public func deleteSession(_ session: SessionReference) async throws {
		try await call {
			let id = switch session {
			case .current: "current"
			case let .id(id): id.uuidString.lowercased()
			}
			_ = try await client.deleteSession(path: .init(sessionId: id)).noContent
		}
	}

	// MARK: AccountService

	public func account() async throws -> Account {
		try await call { try await Account(client.getMe().ok.body.json) }
	}

	public func updateAccount(_ changes: AccountChanges) async throws -> Account {
		try await call {
			let body = Schemas.UserUpdate(
				dayEnd: changes.dayEnd, dayStart: changes.dayStart, displayName: changes.displayName,
				pursuer: changes.pursuer?.schema, timeZone: changes.timeZone
			)
			return try await Account(client.updateMe(body: .json(body)).ok.body.json)
		}
	}

	public func deleteAccount() async throws {
		try await call { _ = try await client.deleteMe().noContent }
	}

	public func keys() async throws -> [Key] {
		try await call { try await client.listKeys().ok.body.json.map(Key.init) }
	}

	public func createKey(kind: KeyKind, name: String) async throws -> NewKey {
		try await call { try await NewKey(client.createKey(body: .json(.init(kind: kind.schema, name: name))).created.body.json) }
	}

	public func deleteKey(id: UUID) async throws {
		try await call { _ = try await client.deleteKey(path: .init(keyId: id.uuidString.lowercased())).noContent }
	}

	public func profileSettings() async throws -> ProfileSettings {
		try await call { try await ProfileSettings(client.getProfileSettings().ok.body.json) }
	}

	public func updateProfileSettings(handle: String, isPublic: Bool) async throws -> ProfileSettings {
		try await call {
			try await ProfileSettings(client.updateProfileSettings(body: .json(.init(handle: handle, _public: isPublic))).ok.body.json)
		}
	}

	public func publicProfile(handle: String) async throws -> PublicProfile {
		try await call { try await PublicProfile(client.getPublicProfile(path: .init(handle: handle)).ok.body.json) }
	}

	public func reminders() async throws -> Reminders {
		try await call { try await Reminders(client.getReminders().ok.body.json) }
	}

	public func updateReminders(_ reminders: Reminders) async throws -> Reminders {
		try await call { try await Reminders(client.updateReminders(body: .json(reminders.schema)).ok.body.json) }
	}

	public func registerDevice(installationID: UUID, _ registration: DeviceRegistration) async throws {
		try await call {
			let environment: Schemas.ApnsEnvironment = switch registration.environment {
			case .sandbox: .sandbox
			case .production: .production
			}
			let body = Schemas.DeviceRegistration(
				apnsToken: registration.apnsToken, appVersion: registration.appVersion,
				environment: environment, widgetPushToken: registration.widgetPushToken
			)
			_ = try await client.registerDevice(
				path: .init(installationId: installationID.uuidString.lowercased()), body: .json(body)
			).noContent
		}
	}

	public func deleteDevice(installationID: UUID) async throws {
		try await call {
			_ = try await client.deleteDevice(path: .init(installationId: installationID.uuidString.lowercased())).noContent
		}
	}

	// MARK: HabitService

	public func habits() async throws -> [Habit] {
		try await call { try await client.listHabits().ok.body.json.map(Habit.init) }
	}

	public func createHabit(_ draft: HabitDraft) async throws -> Habit {
		try await call {
			let body = Schemas.HabitCreate(chunk: draft.chunk, name: draft.name, target: draft.target, unit: draft.unit)
			return try await Habit(client.createHabit(body: .json(body)).created.body.json)
		}
	}

	public func updateHabit(id: UUID, _ changes: HabitChanges) async throws -> Habit {
		try await call {
			let body = Schemas.HabitUpdate(
				chunk: changes.chunk, name: changes.name, position: changes.position, target: changes.target, unit: changes.unit
			)
			return try await Habit(client.updateHabit(path: .init(habitId: id.uuidString.lowercased()), body: .json(body)).ok.body.json)
		}
	}

	public func archiveHabit(id: UUID) async throws -> Habit {
		try await call { try await Habit(client.archiveHabit(path: .init(habitId: id.uuidString.lowercased())).ok.body.json) }
	}

	// MARK: LogService

	public func createLog(_ request: LogRequest) async throws -> LogResult {
		try await call {
			let body = Schemas.LogCreate(
				amount: request.amount, habitId: request.habitID.uuidString.lowercased(),
				id: request.id.uuidString.lowercased(), loggedAt: request.loggedAt, source: request.source.schema
			)
			// 201 for a new log, 200 when this ID was already logged: the same result either way.
			switch try await client.createLog(body: .json(body)) {
			case let .created(created): return try LogResult(created.body.json)
			case let .ok(ok): return try LogResult(ok.body.json)
			case let other: throw APIError.unexpectedResponse("createLog answered \(other)")
			}
		}
	}

	public func undoLog(id: UUID) async throws -> LogResult {
		try await call { try await LogResult(client.undoLog(path: .init(logId: id.uuidString.lowercased())).ok.body.json) }
	}

	public func logs(on date: LocalDate) async throws -> [LogEntry] {
		try await call { try await client.listLogs(query: .init(date: date.rawValue)).ok.body.json.map(LogEntry.init) }
	}

	// MARK: ChaseService

	public func today() async throws -> Chase {
		try await call { try await Chase(client.getChaseToday().ok.body.json) }
	}

	public func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] {
		try await call { try await client.listDays(query: .init(from: from.rawValue, to: to.rawValue)).ok.body.json.map(DaySummary.init) }
	}
}
