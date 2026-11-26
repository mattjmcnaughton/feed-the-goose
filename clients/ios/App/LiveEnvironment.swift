import Foundation
import GooseAPI
import GooseCore
import HTTPTypes
import OpenAPIRuntime
import WidgetKit

/// The composition root: the one place in the app that builds live services. It resolves the
/// server and builds the `AppEnvironment` that every feature's entry view takes, the identity
/// provider for sign-in, and the stream of refused sessions that returns the app to sign-in.
struct LiveEnvironment {
	let server: APIServer
	let app: AppEnvironment
	/// Nil in a build with no way to sign in yet: release builds until the Auth0 sheet lands.
	let identity: (any IdentityProvider)?
	/// Yields when the server answers 401 to a request made with the stored session.
	let refusals: AsyncStream<Void>
	let reloadWidgets: @Sendable () -> Void

	/// The server's address, so views need not see `GooseAPI` types.
	var baseURL: URL { server.baseURL }

	/// The server comes from the `FTGAPIBaseURL` Info.plist key. A `-FTGAPIBaseURL <url>` launch
	/// argument overrides it, because launch arguments sit in front of the app's defaults. In
	/// debug builds `-FTGUseFixtures` runs the app on the fake environment, built from the
	/// fixtures, and records that in the App Group so the widgets and the intents follow. With it,
	/// `-FTGFreshAccount` starts the fake account with no habits, so the app opens on setup.
	static func make(
		defaults: UserDefaults = .standard,
		bundle: Bundle = .main,
		arguments: [String] = ProcessInfo.processInfo.arguments
	) -> LiveEnvironment {
		// The session token lives only in the Keychain. The shared URL cache writes requests
		// and responses to Library/Caches, Authorization header and session response included,
		// so it is turned off before the first request. The API is never read from a cache.
		URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
		let configured = defaults.string(forKey: "FTGAPIBaseURL")
			?? bundle.object(forInfoDictionaryKey: "FTGAPIBaseURL") as? String
		guard let configured, let url = URL(string: configured) else {
			preconditionFailure("FTGAPIBaseURL is missing or is not a URL: \(configured ?? "nil")")
		}
		let server = APIServer(baseURL: url)

		let appGroup = bundle.object(forInfoDictionaryKey: "FTGAppGroup") as? String ?? ""
		guard let shared = SharedStore(appGroup: appGroup) else {
			preconditionFailure("No App Group container for \(appGroup): check the entitlements")
		}
		#if DEBUG
			let useFixtures = arguments.contains("-FTGUseFixtures")
		#else
			let useFixtures = false
		#endif
		shared.setUsesFixtures(useFixtures)
		let reloadWidgets: @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
		let (refusals, refused) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
		if useFixtures {
			#if DEBUG
				let identity: (any IdentityProvider)? = FixtureIdentityProvider()
			#else
				let identity: (any IdentityProvider)? = nil
			#endif
			return LiveEnvironment(
				server: server,
				app: .fake(
					shared: shared.fixtureStore, freshAccount: arguments.contains("-FTGFreshAccount"),
					reloadWidgets: reloadWidgets
				),
				identity: identity, refusals: refusals, reloadWidgets: reloadWidgets
			)
		}

		let session = SessionStore(accessGroup: bundle.object(forInfoDictionaryKey: "FTGKeychainAccessGroup") as? String)
		let transport = RefusalObservingTransport(base: server.makeTransport(), session: session, refused: refused)
		let services = LiveServices(server: server, token: { try session.token() }, transport: transport)
		let app = AppEnvironment(
			auth: services, account: services, habits: services, logs: services, chase: services,
			session: session, shared: shared, reloadWidgets: reloadWidgets
		)
		#if DEBUG
			let identity: (any IdentityProvider)? = DevIdentityProvider(baseURL: url)
		#else
			let identity: (any IdentityProvider)? = nil
		#endif
		return LiveEnvironment(server: server, app: app, identity: identity, refusals: refusals, reloadWidgets: reloadWidgets)
	}
}

/// Watches every response for a 401 to a request that carried the stored session, so a refusal
/// anywhere, from any feature, returns the app to sign-in. A 401 for a token that has since
/// been replaced, such as a request in flight across a new sign-in, is ignored.
struct RefusalObservingTransport: ClientTransport {
	let base: any ClientTransport
	let session: SessionStore
	let refused: AsyncStream<Void>.Continuation

	func send(
		_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
	) async throws -> (HTTPResponse, HTTPBody?) {
		let (response, responseBody) = try await base.send(request, body: body, baseURL: baseURL, operationID: operationID)
		if response.status.code == 401,
		   let sent = request.headerFields[.authorization],
		   let current = try? session.token(),
		   sent == "Bearer \(current)" {
			refused.yield()
		}
		return (response, responseBody)
	}
}
