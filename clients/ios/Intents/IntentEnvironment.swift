import Foundation
import GooseAPI
import GooseCore
import WidgetKit

/// The composition root of the widget extension, and of the intents in either process: the
/// twin of `App/LiveEnvironment.swift` for code that gets no launch arguments. It lives in
/// `Intents/` because the intents run in the app too (from Shortcuts) and in the extension (from
/// a widget button), and both must build the same environment.
///
/// A debug app launched with `-FTGUseFixtures` records that in the App Group, so the widgets
/// and the intents then run on the fake environment over the same fixture store as the app.
enum IntentEnvironment {
	/// Nil when the process has no App Group container, which only a broken build can cause.
	/// `reloadsWidgets` is false for a widget's own timeline, which must not reload itself.
	static func make(reloadsWidgets: Bool = true, bundle: Bundle = .main, defaults: UserDefaults = .standard) -> AppEnvironment? {
		let appGroup = bundle.object(forInfoDictionaryKey: "FTGAppGroup") as? String ?? ""
		guard let shared = SharedStore(appGroup: appGroup) else { return nil }
		let reloadWidgets: @Sendable () -> Void = { if reloadsWidgets { WidgetCenter.shared.reloadAllTimelines() } }
		#if DEBUG
			if shared.usesFixtures {
				return .fake(shared: shared.fixtureStore, reloadWidgets: reloadWidgets)
			}
		#endif
		let configured = defaults.string(forKey: "FTGAPIBaseURL")
			?? bundle.object(forInfoDictionaryKey: "FTGAPIBaseURL") as? String
		guard let configured, let url = URL(string: configured) else { return nil }
		let session = SessionStore(accessGroup: bundle.object(forInfoDictionaryKey: "FTGKeychainAccessGroup") as? String)
		let services = LiveServices(server: APIServer(baseURL: url), token: { try session.token() })
		return AppEnvironment(
			auth: services, account: services, habits: services, logs: services, chase: services,
			session: session, shared: shared, reloadWidgets: reloadWidgets
		)
	}
}
