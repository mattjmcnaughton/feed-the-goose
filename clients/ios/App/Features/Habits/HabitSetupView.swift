import GooseCore
import SwiftUI

/// The first run: the app asks for the user's habits before it shows a chase (PRD S2).
/// `RootView` adds the Done button, which moves on once the server has a habit.
struct HabitSetupView: View {
	@State private var model: HabitsModel

	init(environment: AppEnvironment) {
		_model = State(initialValue: HabitsModel(environment: environment))
	}

	init(model: HabitsModel) {
		_model = State(initialValue: model)
	}

	var body: some View {
		HabitList(model: model) {
			Section {
				VStack(alignment: .leading, spacing: 8) {
					Text("What will you do each day?")
						.font(.custom("Shrikhand-Regular", size: 24, relativeTo: .title))
						.fixedSize(horizontal: false, vertical: true)
						.accessibilityAddTraits(.isHeader)
					Text("Each habit you log keeps you ahead of the goose. Add up to \(HabitsModel.cap), such as Pushups, 50 reps, 10 a tap.")
						.font(.body)
					Text("The goose starts walking when you add your first habit.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				.foregroundStyle(SignInPalette.ink)
				.padding(.vertical, 4)
			}
		}
		.navigationTitle("Your habits")
		.navigationBarTitleDisplayMode(.inline)
		.task { await model.load() }
		.accessibilityIdentifier("habitSetup")
	}
}
