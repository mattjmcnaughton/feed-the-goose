import SwiftUI

/// What each feature's entry view shows until its ticket replaces it.
struct PlaceholderScreen: View {
	let title: String
	let ticket: String

	var body: some View {
		ContentUnavailableView(title, systemImage: "hammer", description: Text("Built in \(ticket)."))
			.navigationTitle(title)
	}
}
