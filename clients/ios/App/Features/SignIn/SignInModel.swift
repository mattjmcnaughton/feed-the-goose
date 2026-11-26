import Foundation
import GooseCore
import Observation

/// The sign-in screen's state: the email being typed, and what became of the last attempt.
@MainActor @Observable
final class SignInModel {
	enum State: Equatable {
		case idle
		case working
		/// The server verified the email but it is not on the allowlist.
		case refused(email: String)
		/// The attempt failed for another reason; the message says what to do.
		case failed(String)
	}

	var email: String
	private(set) var state: State
	/// Why the user was signed out, when the server ended the session.
	let notice: String?
	/// False in a build with no way to sign in yet.
	let isAvailable: Bool
	/// Shown under the form in debug builds, so a run shows which server it talks to.
	let server: String?

	private let signIn: @MainActor (String) async throws -> Void

	init(
		email: String = "",
		state: State = .idle,
		notice: String? = nil,
		isAvailable: Bool = true,
		server: String? = nil,
		signIn: @escaping @MainActor (String) async throws -> Void
	) {
		self.email = email
		self.state = state
		self.notice = notice
		self.isAvailable = isAvailable
		self.server = server
		self.signIn = signIn
	}

	var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
	var canSubmit: Bool { isAvailable && !trimmedEmail.isEmpty && state != .working }

	func submit() async {
		guard canSubmit else { return }
		let email = trimmedEmail
		state = .working
		do {
			try await signIn(email)
			state = .idle
		} catch {
			state = Self.state(after: error, email: email)
		}
	}

	/// What to tell the user about a failed attempt.
	static func state(after error: any Error, email: String) -> State {
		switch error as? APIError {
		case .identityNotAdmitted:
			.refused(email: email)
		case .transport:
			.failed("Couldn't reach the server. Check your connection and try again.")
		case .invalid:
			.failed("That doesn't look like an email address.")
		default:
			error is SessionStoreError
				? .failed("Couldn't save your sign-in on this phone. Try again.")
				: .failed("Something went wrong signing in. Try again.")
		}
	}
}
