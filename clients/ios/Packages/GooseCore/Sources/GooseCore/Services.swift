import Foundation

// The server's operations, as the app uses them. GooseAPI implements them over HTTP; the fakes
// answer from the fixtures. Every method throws `APIError`.

/// Which app session to delete.
public enum SessionReference: Hashable, Sendable {
	/// The session making the request: signing out.
	case current
	case id(UUID)
}

public protocol AuthService: Sendable {
	/// Swaps an identity token for an app session. `timeZone` is used only when the account is
	/// created.
	func createSession(identityToken: String, timeZone: String, deviceName: String) async throws -> NewSession
	func sessions() async throws -> [AppSession]
	func deleteSession(_ session: SessionReference) async throws
}

public protocol AccountService: Sendable {
	func account() async throws -> Account
	func updateAccount(_ changes: AccountChanges) async throws -> Account
	func deleteAccount() async throws

	func keys() async throws -> [Key]
	func createKey(kind: KeyKind, name: String) async throws -> NewKey
	func deleteKey(id: UUID) async throws

	func profileSettings() async throws -> ProfileSettings
	func updateProfileSettings(handle: String, isPublic: Bool) async throws -> ProfileSettings
	func publicProfile(handle: String) async throws -> PublicProfile

	func reminders() async throws -> Reminders
	func updateReminders(_ reminders: Reminders) async throws -> Reminders
	func registerDevice(installationID: UUID, _ registration: DeviceRegistration) async throws
	func deleteDevice(installationID: UUID) async throws
}

public protocol HabitService: Sendable {
	/// Active and upcoming habits.
	func habits() async throws -> [Habit]
	func createHabit(_ draft: HabitDraft) async throws -> Habit
	func updateHabit(id: UUID, _ changes: HabitChanges) async throws -> Habit
	func archiveHabit(id: UUID) async throws -> Habit
}

public protocol LogService: Sendable {
	/// Sends a log. Sending the same ID again returns the same log.
	func createLog(_ request: LogRequest) async throws -> LogResult
	func undoLog(id: UUID) async throws -> LogResult
	/// A day's logs, newest first, including undone ones.
	func logs(on date: LocalDate) async throws -> [LogEntry]
}

public protocol ChaseService: Sendable {
	/// The current day's chase; during the night, the day that just ended. Throws
	/// `APIError.noChase` when the user has no habit for it.
	func today() async throws -> Chase
	func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary]
}
