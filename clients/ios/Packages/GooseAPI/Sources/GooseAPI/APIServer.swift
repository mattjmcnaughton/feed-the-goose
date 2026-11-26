public import Foundation
public import OpenAPIRuntime
internal import OpenAPIURLSession

/// The server the live services talk to. The contract's paths start with `/v1`, so the
/// generated client takes the server's root.
public struct APIServer: Sendable, Equatable {
	public let baseURL: URL

	public init(baseURL: URL) {
		self.baseURL = baseURL
	}

	/// The transport the generated client uses.
	public func makeTransport() -> any ClientTransport {
		URLSessionTransport()
	}
}
