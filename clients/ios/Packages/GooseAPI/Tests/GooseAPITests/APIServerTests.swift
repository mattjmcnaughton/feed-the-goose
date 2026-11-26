import Foundation
import GooseAPI
import Testing

struct APIServerTests {
	@Test func v1IsUnderTheBaseURL() throws {
		let server = APIServer(baseURL: try #require(URL(string: "http://localhost:8000")))
		#expect(server.v1URL.absoluteString == "http://localhost:8000/v1")
	}
}
