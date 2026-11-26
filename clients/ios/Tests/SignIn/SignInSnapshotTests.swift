import GooseCore
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import FeedTheGoose

/// The sign-in screen in each state, on the pinned iPhone 17 Pro's screen. The references are
/// recorded on the pinned simulator; open them before reporting (TDD §7).
@MainActor
struct SignInSnapshotTests {
	/// The iPhone 17 Pro: 402 x 874 points at 3x.
	static let iPhone17Pro = ViewImageConfig(
		safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
		size: CGSize(width: 402, height: 874),
		traits: UITraitCollection(traitsFrom: [
			UITraitCollection(displayScale: 3),
			UITraitCollection(userInterfaceStyle: .light),
			UITraitCollection(userInterfaceIdiom: .phone),
		])
	)

	func snapshot(_ model: SignInModel, named name: String) {
		let controller = UIHostingController(rootView: SignInView(model: model))
		assertSnapshot(of: controller, as: .image(on: Self.iPhone17Pro, precision: 0.99), named: name, testName: "signIn")
	}

	@Test func idle() {
		snapshot(SignInModel(email: "", server: "http://localhost:8000") { _ in }, named: "idle")
	}

	@Test func working() {
		snapshot(SignInModel(email: "matt@example.com", state: .working, server: "http://localhost:8000") { _ in }, named: "working")
	}

	@Test func refused() {
		snapshot(
			SignInModel(email: "stranger@example.com", state: .refused(email: "stranger@example.com"), server: "http://localhost:8000") { _ in },
			named: "refused"
		)
	}

	@Test func networkError() {
		let failed = SignInModel.state(after: APIError.transport("offline"), email: "matt@example.com")
		snapshot(SignInModel(email: "matt@example.com", state: failed, server: "http://localhost:8000") { _ in }, named: "network-error")
	}

	@Test func signedOutBySession() {
		snapshot(
			SignInModel(email: "", notice: "You were signed out. Sign in again to keep going.", server: "http://localhost:8000") { _ in },
			named: "session-ended"
		)
	}
}
