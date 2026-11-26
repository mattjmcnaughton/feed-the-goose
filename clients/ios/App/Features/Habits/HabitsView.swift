import GooseCore
import SwiftUI

/// The user's habits after setup, opened from Settings: add, edit, reorder and archive.
struct HabitsView: View {
	@State private var model: HabitsModel

	init(environment: AppEnvironment) {
		_model = State(initialValue: HabitsModel(environment: environment))
	}

	init(model: HabitsModel) {
		_model = State(initialValue: model)
	}

	var body: some View {
		HabitList(model: model) {
			EmptyView()
		}
		.navigationTitle("Habits")
		.task { await model.load() }
		.accessibilityIdentifier("habits")
	}
}
