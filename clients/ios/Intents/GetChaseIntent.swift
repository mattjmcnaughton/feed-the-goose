import AppIntents
import Foundation
import GooseCore

/// Says how today's chase stands.
struct GetChaseIntent: AppIntent {
	static let title: LocalizedStringResource = "Get the chase"
	static let description = IntentDescription("Says whether today's chase is running, complete, short or caught, and the lead.")

	init() {}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
		let reply = await perform(in: IntentEnvironment.make())
		return .result(value: reply, dialog: "\(reply)")
	}

	@MainActor
	func perform(in environment: AppEnvironment?) async -> String {
		guard let environment else { return ChaseActions.unavailable }
		return await ChaseActions.describe(in: environment)
	}
}
