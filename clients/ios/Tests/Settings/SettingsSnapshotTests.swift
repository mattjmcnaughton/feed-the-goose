import GooseCore
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import FeedTheGoose

/// Settings in each state the ticket names, at the default type size and at accessibility XL.
/// Recorded on the pinned simulator; open them before reporting (TDD §7).
@MainActor
struct SettingsSnapshotTests {
	static let sizes: [(String, UIContentSizeCategory, CGFloat)] = [
		("default", .large, 1700), ("large-type", .accessibilityExtraLarge, 5200),
	]

	func snapshot(_ view: some View, named name: String, sizes: [(String, UIContentSizeCategory, CGFloat)] = Self.sizes) {
		for (label, size, height) in sizes {
			let controller = UIHostingController(rootView: NavigationStack { view }.environment(Self.session))
			let config = HabitSnapshotTests.device(size, height: height)
			assertSnapshot(of: controller, as: .image(on: config, precision: 0.99), named: "\(name)-\(label)", testName: "settings")
		}
	}

	static let session = SessionModel(environment: .fake, identity: nil)

	/// A loaded model on `server`, with the phone in `zone`.
	func loaded(_ server: FakeAccountServer = FakeAccountServer(), zone: String = "America/New_York") async -> SettingsModel {
		let model = SettingsSamples.model(server, zone: zone)
		await model.load()
		return model
	}

	func settings(_ model: SettingsModel) -> some View {
		SettingsView(model: model, keys: KeysModel(environment: model.environment, server: SettingsSamples.server))
	}

	@Test func everySection() async {
		snapshot(settings(await loaded()), named: "sections")
	}

	@Test func aPendingDayChange() async {
		let model = await loaded()
		_ = await model.saveDay(start: "06:00", end: "01:00", timeZone: "America/New_York")
		snapshot(settings(model), named: "pending")
	}

	@Test func theTimeZonePrompt() async {
		snapshot(settings(await loaded(zone: "Europe/Lisbon")), named: "zone-prompt")
	}

	@Test func remindersOnWithQuietHours() async {
		let model = await loaded()
		await model.setRemindersEnabled(true)
		await model.setQuietHours(QuietHours(start: "22:00", end: "07:00"))
		snapshot(settings(model), named: "reminders-on")
	}

	@Test func aTakenHandle() async {
		let server = FakeAccountServer()
		let model = await loaded(server)
		await server.refuse(with: .handleTaken)
		model.handleDraft = "goose"
		await model.saveProfile(isPublic: true)
		snapshot(settings(model), named: "handle-taken")
	}

	@Test func theProfileOn() async {
		let model = await loaded()
		await model.saveProfile(isPublic: true)
		snapshot(settings(model), named: "profile-on")
	}

	@Test func theDayEditorWithARefusedDay() async {
		let model = await loaded()
		_ = await model.saveDay(start: "09:00", end: "16:30", timeZone: "America/New_York")
		snapshot(DayEditorView(model: model, start: "09:00", end: "16:30"), named: "day-refused", sizes: [("default", .large, 874), ("large-type", .accessibilityExtraLarge, 2000)])
	}

	@Test func theKeysList() async {
		let model = KeysModel(environment: SettingsSamples.environment(FakeAccountServer()), server: SettingsSamples.server)
		await model.load()
		snapshot(KeysView(model: model), named: "keys", sizes: [("default", .large, 874), ("large-type", .accessibilityExtraLarge, 2000)])
	}

	@Test func aNewMCPKeysSecret() {
		let created = NewKey(
			key: Key(id: UUID(), kind: .mcp, name: "Amp", createdAt: Date(), lastUsedAt: nil),
			secret: "ftg_fixture-not-a-real-key-00000000000000000000"
		)
		let keys = KeysModel(environment: .fake, server: SettingsSamples.server)
		snapshot(
			KeySecretView(created: created, command: keys.claudeCommand(secret: created.secret), mcpURL: keys.mcpURL) {},
			named: "new-key-secret", sizes: [("default", .large, 874), ("large-type", .accessibilityExtraLarge, 2400)]
		)
	}
}
