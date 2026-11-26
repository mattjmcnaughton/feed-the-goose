import Foundation
import GooseCore
import Observation

/// Where the user is: signed out, signed in without habits, or signed in (TDD §6.4). `RootView`
/// switches on it. It owns the session token's life: the exchange at sign-in, the habit check
/// on launch, sign-out, and a refused session anywhere returning the app to sign-in.
@MainActor @Observable
final class SessionModel {
	enum State: Equatable {
		/// Reading the Keychain and asking the server for the habits.
		case starting
		case signedOut
		/// Signed in with no habits: the app asks for them before it shows a chase.
		case needsHabits
		case signedIn
		/// Signed in, but the habits could not be read and none are cached, so the app cannot
		/// tell setup from the chase. Never shown as an empty habit list (constitution §8).
		case unreachable
	}

	private(set) var state: State = .starting
	/// Why the user is on the sign-in screen when they did not sign out themselves.
	private(set) var notice: String?

	let environment: AppEnvironment
	private let identity: (any IdentityProvider)?
	private let refusals: AsyncStream<Void>
	private let reloadWidgets: @Sendable () -> Void
	private let deviceName: String
	private let timeZone: @Sendable () -> TimeZone

	/// `refusals` yields each time the server refuses the stored session with a 401, from any
	/// request. `identity` is nil in a build that has no way to sign in yet.
	init(
		environment: AppEnvironment,
		identity: (any IdentityProvider)?,
		refusals: AsyncStream<Void> = AsyncStream { $0.finish() },
		reloadWidgets: @escaping @Sendable () -> Void = {},
		deviceName: String = "iPhone",
		timeZone: @escaping @Sendable () -> TimeZone = { .current }
	) {
		self.environment = environment
		self.identity = identity
		self.refusals = refusals
		self.reloadWidgets = reloadWidgets
		self.deviceName = deviceName
		self.timeZone = timeZone
	}

	/// Whether this build can sign in at all.
	var canSignIn: Bool { identity != nil }

	/// Decides the first state, then returns the app to sign-in whenever the session is refused.
	/// Runs for the life of the root view.
	func run() async {
		await start()
		for await _ in refusals {
			sessionEnded()
		}
	}

	/// Reads the token and, when there is one, asks the server whether the user has habits.
	func start() async {
		let token: String?
		do {
			token = try environment.session.token()
		} catch {
			// The Keychain is locked, such as before the first unlock: not the same as signed out.
			state = .unreachable
			return
		}
		guard token != nil else {
			state = .signedOut
			return
		}
		await checkHabits()
	}

	/// Signs in: an identity token from the provider, swapped for an app session, which is saved
	/// in the Keychain. Throws `APIError`, such as `.identityNotAdmitted` for an email off the
	/// allowlist, or `SessionStoreError` when the Keychain refuses the token.
	func signIn(email: String) async throws {
		guard let identity else { throw APIError.notImplemented }
		let identityToken = try await identity.identityToken(loginHint: email)
		let session = try await environment.auth.createSession(
			identityToken: identityToken, timeZone: timeZone().identifier, deviceName: deviceName
		)
		try environment.session.save(session.sessionToken)
		notice = nil
		await checkHabits()
	}

	/// Asks the server for the habits: none means setup, some means the chase. A failure falls
	/// back to the habits cached in the App Group, and without them the app says it cannot tell.
	func checkHabits() async {
		do {
			let habits = try await environment.habits.habits()
			environment.shared.setHabits(habits)
			state = habits.isEmpty ? .needsHabits : .signedIn
		} catch APIError.unauthenticated {
			sessionEnded()
		} catch {
			if let cached = environment.shared.habits {
				state = cached.isEmpty ? .needsHabits : .signedIn
			} else {
				state = .unreachable
			}
		}
	}

	/// Revokes the session on the server, then forgets it here. The phone signs out even when
	/// the server cannot be reached; that session then lapses unused.
	func signOut() async {
		try? await environment.auth.deleteSession(.current)
		forgetSession()
		notice = nil
		state = .signedOut
	}

	/// The server refused the stored session: it expired or was revoked elsewhere.
	private func sessionEnded() {
		guard state != .signedOut else { return }
		forgetSession()
		notice = "You were signed out. Sign in again to keep going."
		state = .signedOut
	}

	/// Removes the token and the signed-in user's cached chase and habits, so the widgets and
	/// the intents show signed out. Queued logs stay, so a user who signs back in loses none.
	private func forgetSession() {
		environment.session.clear()
		environment.shared.setChaseSnapshot(nil)
		environment.shared.setHabits(nil)
		environment.chaseStore.reload()
		reloadWidgets()
	}
}
