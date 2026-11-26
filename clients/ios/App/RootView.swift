import SwiftUI

/// The root of the app. T14 makes it switch on `SessionModel` between `SignInView`,
/// `HabitSetupView` and the tabs for Today and Settings. Until then it lists each feature's
/// entry view so that every placeholder can be reached.
struct RootView: View {
	let environment: LiveEnvironment

	var body: some View {
		NavigationStack {
			List {
				NavigationLink("Sign in") { SignInView() }
				NavigationLink("Habit setup") { HabitSetupView() }
				NavigationLink("Habits") { HabitsView() }
				NavigationLink("Today") { TodayView() }
				NavigationLink("Settings") { SettingsView() }
				Section("Server") {
					Text(environment.baseURL.absoluteString)
						.accessibilityIdentifier("root.server")
				}
			}
			.navigationTitle("Feed the Goose")
		}
	}
}
