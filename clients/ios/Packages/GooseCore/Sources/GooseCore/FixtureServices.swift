import Foundation

/// Services that answer from the fixtures, for previews, tests and `-FTGUseFixtures`. Logging
/// and undoing change the chase that `today()` returns, so a screen can be driven through a
/// log without a server.
public actor FixtureServices: AuthService, AccountService, HabitService, LogService, ChaseService {
	private var chase: Chase

	/// Starts from `chase`, such as the one another process cached, or the example day's chase.
	public init(chase: Chase? = nil) {
		self.chase = chase ?? Fixtures.response("example-day-07-chase")
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

	/// Counts the log against the fake's current chase, so the chase it returns is newer than the
	/// one cached and a screen or widget moves. This is a stand-in for the server's rules, good
	/// enough for fixtures: a habit's share of 100 steps, in proportion to its target, and no
	/// walking between logs. A repeated ID returns the same log, as the server does.
	public func createLog(_ request: LogRequest) async throws -> LogResult {
		if let existing = results[request.id] { return existing }
		guard let index = chase.habits.firstIndex(where: { $0.habitID == request.habitID }) else { throw APIError.notFound }
		let habit = chase.habits[index]
		let amount = request.amount ?? habit.chunk
		let counted = min(amount, max(0, habit.target - habit.logged))
		let steps = Self.tenths(100 / Double(chase.habits.count) * Double(counted) / Double(habit.target))
		let log = LogEntry(
			id: request.id, habitID: request.habitID, amount: amount, loggedAt: request.loggedAt,
			source: request.source, date: chase.date, steps: steps, undoneAt: nil
		)
		chase.habits[index].logged += amount
		chase.habits[index].done = chase.habits[index].logged >= habit.target
		let completes = move(habit: index, by: steps)
		logs.insert(log, at: 0)
		let result = LogResult(log: log, event: ChaseEvent(kind: completes ? .complete : .gain, habitID: request.habitID, steps: steps), chase: chase)
		results[request.id] = result
		return result
	}

	public func undoLog(id: UUID) async throws -> LogResult {
		guard let index = logs.firstIndex(where: { $0.id == id && $0.undoneAt == nil }),
		      let habit = chase.habits.firstIndex(where: { $0.habitID == logs[index].habitID })
		else { throw APIError.notFound }
		logs[index].undoneAt = chase.asOf
		let log = logs[index]
		chase.habits[habit].logged -= log.amount
		chase.habits[habit].done = chase.habits[habit].logged >= chase.habits[habit].target
		move(habit: habit, by: -log.steps)
		return LogResult(log: log, event: ChaseEvent(kind: .undone, habitID: log.habitID, steps: log.steps), chase: chase)
	}

	public func logs(on date: LocalDate) async throws -> [LogEntry] { logs }

	private var logs: [LogEntry] = Fixtures.response("example-day-08-logs")
	private var results: [UUID: LogResult] = [:]

	/// Moves the lead and the habit's steps, advances `asOf`, and settles whether the day is
	/// complete. Returns true when this change completed it.
	@discardableResult
	private func move(habit index: Int, by steps: Double) -> Bool {
		let wasComplete = chase.state == .complete
		chase.habits[index].steps = Self.tenths(chase.habits[index].steps + steps)
		chase.lead = Self.tenths(chase.lead + steps)
		chase.earned = Self.tenths(chase.earned + steps)
		chase.asOf += 1
		let complete = chase.habits.allSatisfy(\.done)
		chase.state = complete ? .complete : .running
		chase.streak.completeDays += (complete ? 1 : 0) - (wasComplete ? 1 : 0)
		return complete && !wasComplete
	}

	private static func tenths(_ value: Double) -> Double { (value * 10).rounded() / 10 }

	// MARK: ChaseService

	public func today() async throws -> Chase { chase }
	public func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { Fixtures.response("days-list") }
}
