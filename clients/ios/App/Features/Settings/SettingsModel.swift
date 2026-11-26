import Foundation
import GooseCore
import Observation

/// Settings (PRD S12 to S16): the day and its time zone, reminders, the public profile, the
/// app sessions and deleting the account. Every change goes to the server, and the screen
/// shows what the server answered, so a day change shows as pending until tomorrow.
@MainActor @Observable
final class SettingsModel {
	enum State: Equatable {
		case loading
		case loaded
		/// The settings could not be read. Never shown as defaults (constitution §8).
		case failed(String)
	}

	private(set) var state: State = .loading
	private(set) var account: Account?
	private(set) var reminders: Reminders?
	private(set) var profile: ProfileSettings?
	private(set) var sessions: [AppSession] = []

	/// The handle being typed, saved with the profile switch or the Save button.
	var handleDraft = ""
	/// Why the last change did not happen, shown at the top.
	var problem: String?
	/// Why the day's hours were refused.
	var dayProblem: String?
	var profileProblem: String?
	/// What turning reminders on did on this phone, such as no push token.
	private(set) var pushNotice: String?
	/// Whether the last attempt to turn reminders on reached the server with a token.
	private(set) var pushOutcome: PushOutcome?
	private(set) var working = false

	/// The zone the user said "Not now" to. The prompt stays away until the phone moves again.
	private var declinedZone: String?

	let environment: AppEnvironment
	let server: URL
	let push: PushRegistrar
	private let deviceZone: @Sendable () -> TimeZone

	init(
		environment: AppEnvironment,
		server: URL,
		notifications: any RemoteNotifications,
		deviceZone: @escaping @Sendable () -> TimeZone = { .current }
	) {
		self.environment = environment
		self.server = server
		push = PushRegistrar(environment: environment, notifications: notifications)
		self.deviceZone = deviceZone
	}

	// MARK: Loading

	func load() async {
		let service = environment.account
		let auth = environment.auth
		do {
			async let account = service.account()
			async let reminders = service.reminders()
			async let profile = service.profileSettings()
			async let sessions = auth.sessions()
			let loaded = try await (account, reminders, profile, sessions)
			self.account = loaded.0
			self.reminders = loaded.1
			self.profile = loaded.2
			self.sessions = loaded.3
			handleDraft = loaded.2.handle ?? ""
			state = .loaded
		} catch {
			let message = Self.message(for: error)
			if state == .loaded { problem = message } else { state = .failed(message) }
		}
	}

	// MARK: The day

	/// The day settings tomorrow will use: the pending ones when there are any.
	var upcoming: (timeZone: String, dayStart: String, dayEnd: String)? {
		guard let account else { return nil }
		if let pending = account.pending { return (pending.timeZone, pending.dayStart, pending.dayEnd) }
		return (account.timeZone, account.dayStart, account.dayEnd)
	}

	/// Saves the day's hours and zone. The server holds them until the next day starts, and
	/// the account comes back with them under `pending`. Returns whether they were saved.
	func saveDay(start: String, end: String, timeZone: String) async -> Bool {
		if let problem = DayWindow.problem(start: start, end: end) {
			dayProblem = problem
			return false
		}
		guard let upcoming else { return false }
		let changes = AccountChanges(
			timeZone: timeZone == upcoming.timeZone ? nil : timeZone,
			dayStart: start == upcoming.dayStart ? nil : start,
			dayEnd: end == upcoming.dayEnd ? nil : end
		)
		guard changes != AccountChanges() else {
			dayProblem = nil
			return true
		}
		return await updateAccount(changes)
	}

	// MARK: The time zone prompt

	/// The phone's zone when it differs from the one the day will use, so the app asks before
	/// changing it (decision D7). Nil once the user said "Not now" to this zone.
	var zonePrompt: String? {
		guard state == .loaded, let upcoming else { return nil }
		let device = deviceZone().identifier
		return device == upcoming.timeZone || device == declinedZone ? nil : device
	}

	func acceptZone() async {
		guard let zone = zonePrompt else { return }
		_ = await updateAccount(AccountChanges(timeZone: zone))
	}

	/// Changes nothing on the server.
	func declineZone() {
		declinedZone = deviceZone().identifier
	}

	private func updateAccount(_ changes: AccountChanges) async -> Bool {
		working = true
		defer { working = false }
		do {
			account = try await environment.account.updateAccount(changes)
			dayProblem = nil
			problem = nil
			return true
		} catch let APIError.invalid(errors) where !errors.isEmpty {
			dayProblem = errors.map(\.message).joined(separator: " ")
		} catch {
			dayProblem = Self.message(for: error)
		}
		return false
	}

	// MARK: Reminders

	/// Turning reminders on asks for notification permission and registers this phone first.
	/// If the user refuses, reminders stay off, because none could show.
	func setRemindersEnabled(_ on: Bool) async {
		guard var wanted = reminders, wanted.enabled != on else { return }
		if on {
			working = true
			let outcome: PushOutcome
			do {
				outcome = try await push.register()
			} catch {
				working = false
				problem = Self.message(for: error)
				return
			}
			working = false
			pushOutcome = outcome
			switch outcome {
			case .registered:
				pushNotice = nil
			case .denied:
				pushNotice = "Notifications are off for Feed the Goose. Turn them on in the Settings app to get reminders."
				return
			case let .noToken(reason):
				pushNotice = "Reminders are on, but this phone has no push token, so they can't reach it yet. iOS said: \(reason)"
			}
		}
		wanted.enabled = on
		await saveReminders(wanted)
	}

	func setThreshold(_ steps: Int) async {
		guard var wanted = reminders else { return }
		wanted.whenLeadBelow = steps
		await saveReminders(wanted)
	}

	func setQuietHours(_ hours: QuietHours?) async {
		guard var wanted = reminders else { return }
		wanted.quietHours = hours
		await saveReminders(wanted)
	}

	private func saveReminders(_ wanted: Reminders) async {
		do {
			reminders = try await environment.account.updateReminders(wanted)
			problem = nil
		} catch {
			problem = Self.message(for: error)
		}
	}

	// MARK: The public profile

	/// The server's rule for a handle: 3 to 30 of a to z, 0 to 9 and "-".
	static func handleProblem(_ handle: String) -> String? {
		let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
		guard (3 ... 30).contains(handle.count), handle.allSatisfy(allowed.contains) else {
			return "A handle is 3 to 30 characters: a to z, 0 to 9 and -."
		}
		return nil
	}

	/// Saves the handle being typed with the profile on or off.
	func saveProfile(isPublic: Bool) async {
		let handle = handleDraft.trimmingCharacters(in: .whitespaces).lowercased()
		handleDraft = handle
		if let problem = Self.handleProblem(handle) {
			profileProblem = problem
			return
		}
		working = true
		defer { working = false }
		do {
			profile = try await environment.account.updateProfileSettings(handle: handle, isPublic: isPublic)
			handleDraft = profile?.handle ?? handle
			profileProblem = nil
		} catch APIError.handleTaken {
			profileProblem = "Someone else has \(handle). Try another handle."
		} catch APIError.invalid {
			profileProblem = "\(handle) can't be used as a handle. Try another."
		} catch {
			profileProblem = Self.message(for: error)
		}
	}

	/// The page anyone can open while the profile is on.
	var profileURL: URL? {
		guard let profile, profile.isPublic, let handle = profile.handle else { return nil }
		return server.appending(path: handle)
	}

	// MARK: Sessions and the account

	func revoke(_ session: AppSession) async {
		do {
			try await environment.auth.deleteSession(.id(session.id))
			sessions = try await environment.auth.sessions()
			problem = nil
		} catch {
			problem = Self.message(for: error)
		}
	}

	/// Removes this phone's push registration. Call it before signing out.
	func prepareSignOut() async {
		await push.unregister()
	}

	/// Deletes the account and everything in it. Returns whether the server did, after which
	/// the caller signs out.
	func deleteAccount() async -> Bool {
		working = true
		defer { working = false }
		do {
			try await environment.account.deleteAccount()
			return true
		} catch {
			problem = Self.message(for: error)
			return false
		}
	}

	/// A sentence for a failure that is not about one field.
	static func message(for error: any Error) -> String {
		switch error as? APIError {
		case .transport, .credentialUnavailable: "Couldn't reach the server. Check your connection and try again."
		case .notFound: "That is no longer there. Pull to refresh."
		case .rateLimited: "Too many changes at once. Wait a moment and try again."
		case let .invalid(errors) where !errors.isEmpty: errors.map(\.message).joined(separator: " ")
		default: "Something went wrong. Try again."
		}
	}
}
