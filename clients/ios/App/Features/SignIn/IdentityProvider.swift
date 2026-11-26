import Foundation
import GooseCore

/// Proves who is signing in and returns an identity token, which `SessionModel` swaps for an
/// app session at `POST /v1/auth/session` (TDD §6.4). The dev provider is the only one until
/// the Auth0 sheet lands behind this same protocol.
protocol IdentityProvider: Sendable {
	/// An identity token for the person signing in. `loginHint` is the email they entered; the
	/// Auth0 provider will pass it to the sheet as `login_hint`. Throws `APIError`.
	func identityToken(loginHint: String) async throws -> String
}

#if DEBUG
	/// The dev sign-in: `POST /dev/token` issues a token for any email, which the server accepts
	/// only in development and tests. Compiled only into debug builds.
	struct DevIdentityProvider: IdentityProvider {
		let baseURL: URL
		/// Ephemeral, so the identity token is never written to a disk cache.
		var session = URLSession(configuration: .ephemeral)

		private struct Request: Encodable { let email: String }
		private struct Response: Decodable { let identity_token: String }

		func identityToken(loginHint: String) async throws -> String {
			var request = URLRequest(url: baseURL.appending(path: "dev/token"), timeoutInterval: 10)
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try JSONEncoder().encode(Request(email: loginHint))
			let data: Data
			let response: URLResponse
			do {
				(data, response) = try await session.data(for: request)
			} catch {
				throw APIError.transport(String(describing: error))
			}
			let status = (response as? HTTPURLResponse)?.statusCode ?? 0
			switch status {
			case 200 ..< 300:
				guard let body = try? JSONDecoder().decode(Response.self, from: data) else {
					throw APIError.unexpectedResponse("POST /dev/token returned no identity_token")
				}
				return body.identity_token
			case 422:
				throw APIError.invalid([FieldError(field: "email", message: "Not an email address")])
			default:
				throw APIError.unexpectedResponse("POST /dev/token returned HTTP \(status)")
			}
		}
	}

	/// The identity for the fake environment (`-FTGUseFixtures`), which needs no server.
	struct FixtureIdentityProvider: IdentityProvider {
		func identityToken(loginHint: String) async throws -> String { "fixture-identity-token" }
	}
#endif
