import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// The server the live services talk to. A placeholder until T13 adds the generated client
/// under `Generated/` and the live services.
public struct APIServer: Sendable, Equatable {
	public let baseURL: URL

	public init(baseURL: URL) {
		self.baseURL = baseURL
	}

	/// The `/v1` root that every generated operation is relative to.
	public var v1URL: URL {
		baseURL.appending(path: "v1")
	}

	/// The transport the generated client will use.
	public func makeTransport() -> any ClientTransport {
		URLSessionTransport()
	}
}
