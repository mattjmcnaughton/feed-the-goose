internal import Foundation
internal import GooseCore
import HTTPTypes
internal import OpenAPIRuntime

/// Adds `Authorization: Bearer <token>` to every request that needs a credential, reading the
/// token on each request, so signing in or out takes effect at once.
struct BearerTokenMiddleware: ClientMiddleware {
	/// The operations that take no credential: the session exchange and the public profile.
	static let publicOperations: Set<String> = ["createSession", "getPublicProfile"]

	let token: @Sendable () throws -> String?

	func intercept(
		_ request: HTTPRequest,
		body: HTTPBody?,
		baseURL: URL,
		operationID: String,
		next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
	) async throws -> (HTTPResponse, HTTPBody?) {
		var request = request
		if !Self.publicOperations.contains(operationID) {
			let token: String?
			do { token = try self.token() } catch { throw APIError.credentialUnavailable }
			if let token { request.headerFields[.authorization] = "Bearer \(token)" }
		}
		return try await next(request, body, baseURL)
	}
}

/// Turns every error response into an `APIError` by its problem `type`, decoded with the
/// generated `Problem` schema. The services therefore see only success responses.
struct ProblemMiddleware: ClientMiddleware {
	func intercept(
		_ request: HTTPRequest,
		body: HTTPBody?,
		baseURL: URL,
		operationID: String,
		next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
	) async throws -> (HTTPResponse, HTTPBody?) {
		let (response, responseBody) = try await next(request, body, baseURL)
		guard response.status.code >= 400 else { return (response, responseBody) }
		var data = Data()
		if let responseBody { data = try await Data(collecting: responseBody, upTo: 1 << 16) }
		throw Self.error(status: response.status.code, body: data)
	}

	/// The error for a response with `status` and `body`.
	static func error(status: Int, body: Data) -> APIError {
		guard let problem = try? JSONDecoder().decode(Components.Schemas.Problem.self, from: body) else {
			return .unexpectedResponse("HTTP \(status) without a problem body")
		}
		return APIError(problem)
	}
}

extension APIError {
	init(_ problem: Components.Schemas.Problem) {
		switch problem._type {
		case .unauthenticated: self = .unauthenticated
		case .identityNotAdmitted: self = .identityNotAdmitted
		case .notFound: self = .notFound
		case .noChase: self = .noChase
		case .daySettled: self = .daySettled
		case .handleTaken: self = .handleTaken
		case .invalid: self = .invalid((problem.errors ?? []).map { FieldError(field: $0.field, message: $0.message) })
		case .rateLimited: self = .rateLimited
		case .notImplemented: self = .notImplemented
		}
	}

	/// Any error from a generated client call, as an `APIError`.
	init(_ error: any Error) {
		switch error {
		case let error as APIError:
			self = error
		case let error as ClientError:
			if let underlying = error.underlyingError as? APIError {
				self = underlying
			} else if error.underlyingError is URLError {
				// Includes a connection dropped while a response body was arriving.
				self = .transport(String(describing: error.underlyingError))
			} else if let response = error.response {
				self = .unexpectedResponse("HTTP \(response.status.code): \(error.underlyingError)")
			} else {
				self = .transport(String(describing: error.underlyingError))
			}
		default:
			self = .unexpectedResponse(String(describing: error))
		}
	}
}
