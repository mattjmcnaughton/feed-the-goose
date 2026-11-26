import GooseCore
import SwiftUI

/// What each feature's entry view shows until its ticket replaces it: the ticket, and the chase
/// that `ChaseStore` holds, so a run shows which environment the app is on.
struct PlaceholderScreen: View {
	let title: String
	let ticket: String
	let environment: AppEnvironment

	var body: some View {
		List {
			ContentUnavailableView(title, systemImage: "hammer", description: Text("Built in \(ticket)."))
			if let snapshot = environment.chaseStore.snapshot {
				Section("Chase on \(snapshot.chase.date)") {
					LabeledContent("State", value: snapshot.chase.state.rawValue)
					TimelineView(.periodic(from: .now, by: 1)) { context in
						LabeledContent("Lead", value: snapshot.clock.lead(at: context.date).formatted(.number.precision(.fractionLength(1))))
					}
					.accessibilityIdentifier("placeholder.lead")
					LabeledContent("Streak", value: "\(snapshot.chase.streak.completeDays) days")
					if snapshot.isOutOfDate {
						Text("Out of date").foregroundStyle(.orange)
					}
				}
				Section("Habits") {
					ForEach(snapshot.chase.habits) { habit in
						LabeledContent(habit.name, value: "\(habit.logged) / \(habit.target) \(habit.unit)")
					}
				}
			}
		}
		.navigationTitle(title)
		.task { await environment.chaseStore.refresh() }
	}
}
