import Foundation
import Testing
@testable import FeedTheGoose

/// The session token must live only in the Keychain. URLSession's shared cache wrote it to
/// Library/Caches in the simulator (with the Authorization header of each cached request), so the
/// composition root turns that cache off.
@Suite(.serialized)
struct TokenStorageTests {
	@Test func theLiveEnvironmentTurnsOffTheSharedURLCache() throws {
		URLCache.shared = URLCache(memoryCapacity: 4_000_000, diskCapacity: 20_000_000)
		let defaults = try #require(UserDefaults(suiteName: "TokenStorageTests"))
		_ = LiveEnvironment.make(defaults: defaults, bundle: .main, arguments: [])
		#expect(URLCache.shared.diskCapacity == 0)
		#expect(URLCache.shared.memoryCapacity == 0)
	}

	@Test func theDevSignInUsesNoDiskCache() {
		let provider = DevIdentityProvider(baseURL: URL(string: "http://localhost:8000")!)
		#expect(provider.session.configuration.urlCache?.diskCapacity ?? 0 == 0)
	}
}
