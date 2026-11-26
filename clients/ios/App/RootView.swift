import GooseCore
import SwiftUI

/// The root of the app. It switches on `SessionModel` between sign-in, habit setup and the tabs
/// for Today and Settings (TDD §6.4), and provides the model to every screen below it.
struct RootView: View {
	let environment: LiveEnvironment
	@State private var session: SessionModel

	init(environment: LiveEnvironment) {
		self.environment = environment
		_session = State(initialValue: SessionModel(
			environment: environment.app,
			identity: environment.identity,
			refusals: environment.refusals,
			reloadWidgets: environment.reloadWidgets
		))
	}

	var body: some View {
		let app = environment.app
		Group {
			switch session.state {
			case .starting:
				ProgressView().accessibilityIdentifier("root.starting")
			case .signedOut:
				SignInView(model: signInModel)
			case .needsHabits:
				NavigationStack {
					HabitSetupView(environment: app)
						.toolbar {
							ToolbarItem(placement: .cancellationAction) { SignOutButton() }
							// Habit setup saves each habit itself; this asks the server again and
							// moves on to the chase once there is one.
							ToolbarItem(placement: .confirmationAction) {
								Button("Done") { Task { await session.checkHabits() } }
									.accessibilityIdentifier("habitSetup.done")
							}
						}
				}
			case .signedIn:
				TabView {
					Tab("Today", systemImage: "figure.run") {
						NavigationStack { TodayView(environment: app) }
					}
					Tab("Settings", systemImage: "gearshape") {
						// Settings has its own sign-out, which also removes the push registration.
						NavigationStack { SettingsView(environment: app) }
					}
				}
			case .unreachable:
				ContentUnavailableView {
					Label("Couldn't reach the server", systemImage: "wifi.exclamationmark")
				} description: {
					Text("Your habits couldn't be loaded. Check your connection and try again.")
				} actions: {
					Button("Try again") { Task { await session.start() } }
						.buttonStyle(.borderedProminent)
					SignOutButton()
				}
				.accessibilityIdentifier("root.unreachable")
			}
		}
		.environment(session)
		.task { await session.run() }
	}

	private var signInModel: SignInModel {
		#if DEBUG
			let server: String? = environment.baseURL.absoluteString
		#else
			let server: String? = nil
		#endif
		return SignInModel(
			notice: session.notice,
			isAvailable: session.canSignIn,
			server: server,
			signIn: { [session] email in try await session.signIn(email: email) }
		)
	}
}
