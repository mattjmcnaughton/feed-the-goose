import Foundation
import Testing
@testable import FeedTheGoose

struct LiveEnvironmentTests {
	@Test func launchArgumentOverridesInfoPlist() throws {
		let defaults = try #require(UserDefaults(suiteName: "LiveEnvironmentTests"))
		defer { defaults.removePersistentDomain(forName: "LiveEnvironmentTests") }
		defaults.set("http://10.0.0.5:9000", forKey: "FTGAPIBaseURL")
		let environment = LiveEnvironment.make(defaults: defaults, bundle: .main)
		#expect(environment.server.baseURL.absoluteString == "http://10.0.0.5:9000")
	}

	@Test func debugBuildsUseTheLocalServer() throws {
		let defaults = try #require(UserDefaults(suiteName: "LiveEnvironmentTests.empty"))
		let environment = LiveEnvironment.make(defaults: defaults, bundle: .main)
		#expect(environment.server.baseURL.absoluteString == "http://localhost:8000")
	}
}
