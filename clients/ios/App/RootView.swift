import SwiftUI

/// The root of the app. T14 makes it switch on `SessionModel` between `SignInView`,
/// `HabitSetupView` and the tabs for Today and Settings. Until then it lists each feature's
/// entry view so that every placeholder can be reached.
struct RootView: View {
	let environment: LiveEnvironment

	var body: some View {
		let app = environment.app
		NavigationStack {
			List {
				NavigationLink("Sign in") { SignInView(environment: app) }
				NavigationLink("Habit setup") { HabitSetupView(environment: app) }
				NavigationLink("Habits") { HabitsView(environment: app) }
				NavigationLink("Today") { TodayView(environment: app) }
				NavigationLink("Settings") { SettingsView(environment: app) }
				Section("Server") {
					Text(environment.baseURL.absoluteString)
						.accessibilityIdentifier("root.server")
					if app.usesFixtures {
						Text("Using fixtures").accessibilityIdentifier("root.fixtures")
					}
				}
			}
			.navigationTitle("Feed the Goose")
		}
	}
}
