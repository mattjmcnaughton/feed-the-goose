import SwiftUI

/// Signs out after a confirmation: revokes the session on the server and removes it from the
/// phone. Reads `SessionModel` from the environment, which `RootView` provides, so Settings can
/// place it anywhere.
struct SignOutButton: View {
	@Environment(SessionModel.self) private var session
	@State private var confirming = false
	@State private var working = false

	var body: some View {
		Button("Sign out", role: .destructive) { confirming = true }
			.disabled(working)
			.accessibilityIdentifier("signOut")
			.confirmationDialog("Sign out of Feed the Goose?", isPresented: $confirming, titleVisibility: .visible) {
				Button("Sign out", role: .destructive) {
					working = true
					Task {
						await session.signOut()
						working = false
					}
				}
			} message: {
				Text("The widgets and Shortcuts stop working until you sign in again.")
			}
	}
}
