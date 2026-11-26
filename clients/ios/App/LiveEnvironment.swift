import Foundation
import GooseAPI

/// The composition root: the one place in the app that builds live services. T13 turns it into
/// an `AppEnvironment` of live services; until then it only resolves the server.
struct LiveEnvironment {
	let server: APIServer

	/// The server's address, so views need not see `GooseAPI` types.
	var baseURL: URL { server.baseURL }

	/// The server comes from the `FTGAPIBaseURL` Info.plist key. A `-FTGAPIBaseURL <url>` launch
	/// argument overrides it, because launch arguments sit in front of the app's defaults.
	static func make(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> LiveEnvironment {
		let configured = defaults.string(forKey: "FTGAPIBaseURL")
			?? bundle.object(forInfoDictionaryKey: "FTGAPIBaseURL") as? String
		guard let configured, let url = URL(string: configured) else {
			preconditionFailure("FTGAPIBaseURL is missing or is not a URL: \(configured ?? "nil")")
		}
		return LiveEnvironment(server: APIServer(baseURL: url))
	}
}
