import Foundation
import GooseAPI
import HTTPTypes
import OpenAPIRuntime

/// A request the stub server received.
struct RecordedRequest: Sendable {
	let method: String
	/// The path with its query.
	let path: String
	let authorization: String?
	let body: Data?

	/// The body as a JSON object.
	var json: [String: Any]? {
		body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
	}
}

/// A transport that answers from a handler instead of the network and records every request.
/// The generated client, the middlewares and the adapters run as they do against the server.
final class StubServer: ClientTransport, @unchecked Sendable {
	typealias Handler = @Sendable (RecordedRequest) async throws -> (status: Int, body: Data?)

	private let lock = NSLock()
	private var recorded: [RecordedRequest] = []
	private let handler: Handler

	init(handler: @escaping Handler) {
		self.handler = handler
	}

	var requests: [RecordedRequest] { lock.withLock { recorded } }

	func services(token: String? = "test-session-token") -> LiveServices {
		LiveServices(server: APIServer(baseURL: URL(string: "http://stub.invalid")!), token: { token }, transport: self)
	}

	func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
		var data: Data?
		if let body { data = try await Data(collecting: body, upTo: 1 << 20) }
		let record = RecordedRequest(
			method: request.method.rawValue,
			path: request.path ?? "",
			authorization: request.headerFields[.authorization],
			body: data
		)
		lock.withLock { recorded.append(record) }
		let (status, responseBody) = try await handler(record)
		var response = HTTPResponse(status: .init(code: status))
		if responseBody != nil {
			response.headerFields[.contentType] = status >= 400 ? "application/problem+json" : "application/json"
		}
		return (response, responseBody.map { HTTPBody($0) })
	}
}
