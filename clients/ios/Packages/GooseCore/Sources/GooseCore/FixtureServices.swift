import Foundation

/// Services that answer from the fixtures, for previews, tests and `-FTGUseFixtures`. Logging
/// and undoing change the chase that `today()` returns, so a screen can be driven through a
/// log without a server.
public actor FixtureServices: AuthService, AccountService, HabitService, LogService, ChaseService {
	private var chase: Chase

	public init() {
		chase = Fixtures.response("example-day-07-chase")
	}

	// MARK: AuthService

	public func createSession(identityToken: String, timeZone: String, deviceName: String) async throws -> NewSession {
		Fixtures.response("auth-session-create")
	}

	public func sessions() async throws -> [AppSession] { Fixtures.response("auth-sessions-list") }
	public func deleteSession(_ session: SessionReference) async throws {}

	// MARK: AccountService

	public func account() async throws -> Account { Fixtures.response("me-get") }
	public func updateAccount(_ changes: AccountChanges) async throws -> Account { Fixtures.response("me-update") }
	public func deleteAccount() async throws {}

	public func keys() async throws -> [Key] { Fixtures.response("keys-list") }
	public func createKey(kind: KeyKind, name: String) async throws -> NewKey { Fixtures.response("keys-create") }
	public func deleteKey(id: UUID) async throws {}

	public func profileSettings() async throws -> ProfileSettings { Fixtures.response("profile-get") }

	public func updateProfileSettings(handle: String, isPublic: Bool) async throws -> ProfileSettings {
		Fixtures.response("profile-update")
	}

	public func publicProfile(handle: String) async throws -> PublicProfile { Fixtures.response("public-profile-get") }

	public func reminders() async throws -> Reminders { Fixtures.response("reminders-get") }
	public func updateReminders(_ reminders: Reminders) async throws -> Reminders { reminders }
	public func registerDevice(installationID: UUID, _ registration: DeviceRegistration) async throws {}
	public func deleteDevice(installationID: UUID) async throws {}

	// MARK: HabitService

	public func habits() async throws -> [Habit] { Fixtures.response("habits-list") }
	public func createHabit(_ draft: HabitDraft) async throws -> Habit { Fixtures.response("habits-create") }
	public func updateHabit(id: UUID, _ changes: HabitChanges) async throws -> Habit { Fixtures.response("habits-update") }
	public func archiveHabit(id: UUID) async throws -> Habit { Fixtures.response("habits-archive") }

	// MARK: LogService

	/// Answers with the example day's first log, carrying the request's own values.
	public func createLog(_ request: LogRequest) async throws -> LogResult {
		var result: LogResult = Fixtures.response("example-day-01-log-pushups")
		result.log.id = request.id
		result.log.habitID = request.habitID
		result.log.loggedAt = request.loggedAt
		result.log.source = request.source
		result.event.habitID = request.habitID
		chase = result.chase
		return result
	}

	public func undoLog(id: UUID) async throws -> LogResult {
		var result: LogResult = Fixtures.response("example-day-06-undo-reading")
		result.log.id = id
		chase = result.chase
		return result
	}

	public func logs(on date: LocalDate) async throws -> [LogEntry] { Fixtures.response("example-day-08-logs") }

	// MARK: ChaseService

	public func today() async throws -> Chase { chase }
	public func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { Fixtures.response("days-list") }
}
