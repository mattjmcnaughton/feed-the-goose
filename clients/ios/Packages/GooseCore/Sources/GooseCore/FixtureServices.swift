import Foundation

/// Services that answer from the fixtures, for previews, tests and `-FTGUseFixtures`. Logging
/// and undoing change the chase that `today()` returns, and adding, editing and archiving
/// change the habits, so a screen can be driven without a server.
public actor FixtureServices: AuthService, AccountService, HabitService, LogService, ChaseService {
	private var chase: Chase
	private var habitList: [Habit]
	private var logs: [LogEntry]
	private var results: [UUID: LogResult] = [:]
	private var accountState: Account = Fixtures.response("me-get")
	private var keyList: [Key] = Fixtures.response("keys-list")
	private var profile = ProfileSettings(handle: "matt", isPublic: false)
	private var reminderState: Reminders = Fixtures.response("reminders-get")

	/// Starts from `chase`, such as the one another process cached, or the example day's chase.
	/// A fresh account has no habits and no logs yet, as after a first sign-in.
	public init(chase: Chase? = nil, freshAccount: Bool = false) {
		self.chase = chase ?? Fixtures.response("example-day-07-chase")
		habitList = freshAccount ? [] : Fixtures.response("habits-list")
		logs = freshAccount ? [] : Fixtures.response("example-day-08-logs")
	}

	// MARK: AuthService

	public func createSession(identityToken: String, timeZone: String, deviceName: String) async throws -> NewSession {
		Fixtures.response("auth-session-create")
	}

	public func sessions() async throws -> [AppSession] { Fixtures.response("auth-sessions-list") }
	public func deleteSession(_ session: SessionReference) async throws {}

	// MARK: AccountService

	// The account, the keys, the profile and the reminders keep what was last saved, so Settings
	// can be driven without a server. A day change waits under `pending` for tomorrow, as on the
	// server. The profile starts off, and the handle "taken" belongs to someone else.

	public func account() async throws -> Account { accountState }

	public func updateAccount(_ changes: AccountChanges) async throws -> Account {
		let base = accountState.pending.map { ($0.timeZone, $0.dayStart, $0.dayEnd) }
			?? (accountState.timeZone, accountState.dayStart, accountState.dayEnd)
		let wanted = (changes.timeZone ?? base.0, changes.dayStart ?? base.1, changes.dayEnd ?? base.2)
		if wanted == (accountState.timeZone, accountState.dayStart, accountState.dayEnd) {
			accountState.pending = nil
		} else {
			accountState.pending = PendingDay(effectiveFrom: Self.dayAfter(chase.date), timeZone: wanted.0, dayStart: wanted.1, dayEnd: wanted.2)
		}
		accountState.displayName = changes.displayName ?? accountState.displayName
		return accountState
	}

	public func deleteAccount() async throws {}

	public func keys() async throws -> [Key] { keyList }

	public func createKey(kind: KeyKind, name: String) async throws -> NewKey {
		let fixture: NewKey = Fixtures.response("keys-create")
		let key = Key(id: .v7(), kind: kind, name: name, createdAt: chase.asOf, lastUsedAt: nil)
		keyList.append(key)
		return NewKey(key: key, secret: fixture.secret)
	}

	public func deleteKey(id: UUID) async throws {
		guard keyList.contains(where: { $0.id == id }) else { throw APIError.notFound }
		keyList.removeAll { $0.id == id }
	}

	public func profileSettings() async throws -> ProfileSettings { profile }

	public func updateProfileSettings(handle: String, isPublic: Bool) async throws -> ProfileSettings {
		if handle == "taken" { throw APIError.handleTaken }
		profile = ProfileSettings(handle: handle, isPublic: isPublic)
		return profile
	}

	public func publicProfile(handle: String) async throws -> PublicProfile { Fixtures.response("public-profile-get") }

	public func reminders() async throws -> Reminders { reminderState }

	public func updateReminders(_ reminders: Reminders) async throws -> Reminders {
		reminderState = reminders
		return reminders
	}

	public func registerDevice(installationID: UUID, _ registration: DeviceRegistration) async throws {}
	public func deleteDevice(installationID: UUID) async throws {}

	// MARK: HabitService

	// These follow the API spec's habit rules, with the fixture chase's date as today: a habit
	// added before the day's first log starts today and otherwise tomorrow, at most 8 habits
	// belong to a day, archiving takes effect tomorrow, and a moved habit renumbers the rest.

	public func habits() async throws -> [Habit] { habitList }

	public func createHabit(_ draft: HabitDraft) async throws -> Habit {
		let tomorrow = Self.dayAfter(chase.date)
		let startsOn = logs.contains { $0.date == chase.date } ? tomorrow : chase.date
		for day in Set([startsOn, tomorrow]) where habitList.count(where: { Self.belongs($0, to: day) }) >= 8 {
			throw APIError.invalid([])
		}
		let habit = Habit(
			id: .v7(), name: draft.name, unit: draft.unit, target: draft.target, chunk: draft.chunk,
			position: (habitList.map(\.position).max() ?? -1) + 1, effectiveFrom: startsOn, archivedFrom: nil
		)
		habitList.append(habit)
		return habit
	}

	public func updateHabit(id: UUID, _ changes: HabitChanges) async throws -> Habit {
		guard let index = habitList.firstIndex(where: { $0.id == id }) else { throw APIError.notFound }
		var habit = habitList[index]
		habit.name = changes.name ?? habit.name
		habit.unit = changes.unit ?? habit.unit
		habit.target = changes.target ?? habit.target
		habit.chunk = changes.chunk ?? habit.chunk
		habitList.remove(at: index)
		habitList.insert(habit, at: changes.position.map { min($0, habitList.count) } ?? index)
		for position in habitList.indices { habitList[position].position = position }
		return habitList.first { $0.id == id }!
	}

	public func archiveHabit(id: UUID) async throws -> Habit {
		guard let index = habitList.firstIndex(where: { $0.id == id }) else { throw APIError.notFound }
		if habitList[index].archivedFrom == nil { habitList[index].archivedFrom = Self.dayAfter(chase.date) }
		return habitList[index]
	}

	private static func belongs(_ habit: Habit, to day: LocalDate) -> Bool {
		habit.effectiveFrom <= day && habit.archivedFrom.map { day < $0 } ?? true
	}

	private static func dayAfter(_ date: LocalDate) -> LocalDate {
		let style = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
		guard let day = try? style.parse(date.rawValue) else { return date }
		return LocalDate(rawValue: (day + 86400).formatted(style))
	}

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
