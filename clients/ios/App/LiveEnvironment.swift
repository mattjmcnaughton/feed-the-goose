import Foundation
import GooseAPI
import GooseCore
import WidgetKit

/// The composition root: the one place in the app that builds live services. It resolves the
/// server and builds the `AppEnvironment` that every feature's entry view takes.
struct LiveEnvironment {
	let server: APIServer
	let app: AppEnvironment

	/// The server's address, so views need not see `GooseAPI` types.
	var baseURL: URL { server.baseURL }

	/// The server comes from the `FTGAPIBaseURL` Info.plist key. A `-FTGAPIBaseURL <url>` launch
	/// argument overrides it, because launch arguments sit in front of the app's defaults. In
	/// debug builds `-FTGUseFixtures` runs the app on the fake environment, built from the
	/// fixtures, and records that in the App Group so the widgets and the intents follow.
	static func make(
		defaults: UserDefaults = .standard,
		bundle: Bundle = .main,
		arguments: [String] = ProcessInfo.processInfo.arguments
	) -> LiveEnvironment {
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
		if useFixtures {
			return LiveEnvironment(server: server, app: .fake(shared: shared.fixtureStore, reloadWidgets: reloadWidgets))
		}

		let session = SessionStore(accessGroup: bundle.object(forInfoDictionaryKey: "FTGKeychainAccessGroup") as? String)
		let services = LiveServices(server: server, token: { try session.token() })
		let app = AppEnvironment(
			auth: services, account: services, habits: services, logs: services, chase: services,
			session: session, shared: shared, reloadWidgets: reloadWidgets
		)
		return LiveEnvironment(server: server, app: app)
	}
}
