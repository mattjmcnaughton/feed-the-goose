import AppIntents
import Foundation
import GooseCore

/// Undoes today's newest log.
struct UndoLastLogIntent: AppIntent {
	static let title: LocalizedStringResource = "Undo the last log"
	static let description = IntentDescription("Undoes today's newest log and says how far behind the goose is.")

	init() {}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
		let reply = await perform(in: IntentEnvironment.make())
		return .result(value: reply, dialog: "\(reply)")
	}

	@MainActor
	func perform(in environment: AppEnvironment?) async -> String {
		guard let environment else { return ChaseActions.unavailable }
		return await ChaseActions.undoLast(in: environment)
	}
}
