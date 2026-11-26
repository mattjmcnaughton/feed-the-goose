import GooseCore
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import FeedTheGoose

/// Habit setup and the habit form in each state the ticket names, at the default type size and
/// at accessibility XL. Recorded on the pinned simulator; open them before reporting.
@MainActor
struct HabitSnapshotTests {
	/// The phone's width; `height` is taller than the screen for a list, so the whole list,
	/// add button included, and the whole form are in the image.
	static func device(_ size: UIContentSizeCategory, height: CGFloat) -> ViewImageConfig {
		var config = SignInSnapshotTests.iPhone17Pro
		config.size?.height = height
		config.traits = UITraitCollection(traitsFrom: [config.traits, UITraitCollection(preferredContentSizeCategory: size)])
		return config
	}

	/// Each type size with the height that fits a list of up to eight habits.
	static let sizes: [(String, UIContentSizeCategory, CGFloat)] = [
		("default", .large, 1400), ("large-type", .accessibilityExtraLarge, 3400),
	]

	func snapshot(_ view: some View, named name: String) {
		for (label, size, height) in Self.sizes {
			let controller = UIHostingController(rootView: NavigationStack { view })
			let config = Self.device(size, height: height)
			assertSnapshot(of: controller, as: .image(on: config, precision: 0.99), named: "\(name)-\(label)", testName: "habits")
		}
	}

	func setup(_ habits: [Habit]) -> some View {
		HabitSetupView(model: HabitsModel(environment: HabitSamples.environment(FakeHabitServer(habits)), habits: habits))
	}

	static let three = [
		Habit(id: UUID(), name: "Pushups", unit: "reps", target: 50, chunk: 10, position: 0, effectiveFrom: "2026-11-26", archivedFrom: nil),
		Habit(id: UUID(), name: "Workout", unit: "minutes", target: 30, chunk: 10, position: 1, effectiveFrom: "2026-11-26", archivedFrom: nil),
		Habit(id: UUID(), name: "Reading", unit: "pages", target: 20, chunk: 5, position: 2, effectiveFrom: "2026-11-26", archivedFrom: nil),
	]

	@Test func emptyFirstRun() { snapshot(setup([]), named: "setup-empty") }

	@Test func threeHabits() { snapshot(setup(Self.three), named: "setup-three") }

	@Test func eightHabitsWithAddDisabled() { snapshot(setup(HabitSamples.habits(8)), named: "setup-eight") }

	@Test func aHabitThatStartsTomorrow() {
		var habits = Self.three
		habits.append(Habit(id: UUID(), name: "Stretching", unit: "minutes", target: 15, chunk: 5, position: 3, effectiveFrom: "2026-11-27", archivedFrom: nil))
		snapshot(setup(habits), named: "setup-starts-tomorrow")
	}

	@Test func theEditFormWithAnError() {
		let model = HabitFormModel(editing: Self.three[0], errors: [.target: "Enter a whole number above 0."]) { _ in }
		model.target = "0"
		snapshot(HabitFormView(model: model), named: "form-error")
	}
}
