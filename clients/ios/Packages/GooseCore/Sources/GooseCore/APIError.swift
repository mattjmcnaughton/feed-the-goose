import Foundation

/// One field that failed validation.
public struct FieldError: Codable, Hashable, Sendable {
	public var field: String
	public var message: String

	public init(field: String, message: String) {
		self.field = field
		self.message = message
	}
}

/// Why a call to the server failed. Each problem `type` in the API has its own case, so a
/// caller can tell a settled day from a network failure (constitution §8).
public enum APIError: Error, Hashable, Sendable {
	case unauthenticated
	case identityNotAdmitted
	case notFound
	/// The user has no habit for the current day.
	case noChase
	/// A log or undo for a day that has already settled.
	case daySettled
	case handleTaken
	case invalid([FieldError])
	case rateLimited
	case notImplemented
	/// A status or body the contract does not describe.
	case unexpectedResponse(String)
	/// The session token could not be read, such as before the first unlock after a restart.
	case credentialUnavailable
	/// The request did not complete: no network, a timeout, or a dropped connection.
	case transport(String)
}
