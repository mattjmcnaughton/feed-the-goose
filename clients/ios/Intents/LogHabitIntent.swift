import AppIntents
import Foundation
import GooseCore

/// Logs a habit from Shortcuts. The log's source is `shortcuts`.
struct LogHabitIntent: AppIntent {
	static let title: LocalizedStringResource = "Log a habit"
	static let description = IntentDescription("Logs an amount of a habit, or its usual chunk, and says how far behind the goose is.")

	@Parameter(title: "Habit")
	var habit: HabitEntity

	@Parameter(title: "Amount", description: "Leave empty to log the habit's chunk.", inclusiveRange: (1, 100_000))
	var amount: Int?

	static var parameterSummary: some ParameterSummary {
		Summary("Log \(\.$amount) of \(\.$habit)")
	}

	init() {}

	init(habit: HabitEntity, amount: Int? = nil) {
		self.habit = habit
		self.amount = amount
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
		let reply = await perform(in: IntentEnvironment.make())
		return .result(value: reply, dialog: "\(reply)")
	}

	@MainActor
	func perform(in environment: AppEnvironment?) async -> String {
		guard let environment else { return ChaseActions.unavailable }
		return await ChaseActions.log(habitID: habit.id, amount: amount, source: .shortcuts, in: environment)
	}
}

/// A Feed widget's button: one chunk of one habit, logged with the source `widget`. It runs in
/// the widget extension and replies only by redrawing the widgets, so Shortcuts does not list it.
struct LogFromWidgetIntent: AppIntent {
	static let title: LocalizedStringResource = "Log a habit from a widget"
	static let isDiscoverable = false

	@Parameter(title: "Habit")
	var habitID: String

	@Parameter(title: "Amount")
	var amount: Int

	init() {}

	init(habitID: UUID, amount: Int) {
		self.habitID = habitID.uuidString
		self.amount = amount
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		_ = await perform(in: IntentEnvironment.make())
		return .result()
	}

	@MainActor
	func perform(in environment: AppEnvironment?) async -> String {
		guard let environment, let id = UUID(uuidString: habitID) else { return ChaseActions.unavailable }
		return await ChaseActions.log(habitID: id, amount: amount, source: .widget, in: environment)
	}
}
