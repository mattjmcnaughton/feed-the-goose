import Foundation
import GooseCore
import Testing

struct UUIDv7Tests {
	@Test func carriesTheTimeVersionAndVariant() {
		// 2026-11-26T14:05:00Z is 1_795_701_900_000 ms, 0x01A2182C82E0: the fixtures' log IDs start so.
		let id = UUID.v7(at: Date(timeIntervalSince1970: 1_795_701_900))
		let text = id.uuidString.lowercased()
		#expect(text.hasPrefix("01a2182c-82e0-7"))
		#expect(["8", "9", "a", "b"].contains(text[text.index(text.startIndex, offsetBy: 19)]))
	}

	@Test func sortsByTime() {
		let earlier = UUID.v7(at: Date(timeIntervalSince1970: 1_795_701_900))
		let later = UUID.v7(at: Date(timeIntervalSince1970: 1_795_701_900.002))
		#expect(earlier.uuidString < later.uuidString)
		#expect(UUID.v7() != UUID.v7())
	}
}
