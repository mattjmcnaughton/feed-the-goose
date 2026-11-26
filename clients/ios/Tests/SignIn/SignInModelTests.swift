import Foundation
import GooseCore
import Testing
@testable import FeedTheGoose

@MainActor
struct SignInModelTests {
	@Test func anEmailOffTheAllowlistIsRefusedByName() async {
		let model = SignInModel(email: "  stranger@example.com ") { _ in throw APIError.identityNotAdmitted }
		await model.submit()
		#expect(model.state == .refused(email: "stranger@example.com"))
	}

	@Test func aNetworkFailureSaysSo() async {
		let model = SignInModel(email: "matt@example.com") { _ in throw APIError.transport("offline") }
		await model.submit()
		#expect(model.state == .failed("Couldn't reach the server. Check your connection and try again."))
	}

	@Test func theTrimmedEmailIsSentAndSuccessReturnsToIdle() async {
		var sent: [String] = []
		let model = SignInModel(email: " matt@example.com\n") { sent.append($0) }
		await model.submit()
		#expect(sent == ["matt@example.com"])
		#expect(model.state == .idle)
	}

	@Test func itIsWorkingWhileTheServerAnswers() async {
		let (gate, open) = AsyncStream.makeStream(of: Void.self)
		let model = SignInModel(email: "matt@example.com") { _ in for await _ in gate {} }
		let submitting = Task { await model.submit() }
		while model.state != .working { await Task.yield() }
		#expect(!model.canSubmit)
		open.finish()
		await submitting.value
		#expect(model.state == .idle)
	}

	@Test func anEmptyEmailOrAnUnavailableBuildSendsNothing() async {
		var calls = 0
		let empty = SignInModel(email: "   ") { _ in calls += 1 }
		await empty.submit()
		let unavailable = SignInModel(email: "matt@example.com", isAvailable: false) { _ in calls += 1 }
		await unavailable.submit()
		#expect(calls == 0)
	}
}
