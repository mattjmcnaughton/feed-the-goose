import Foundation
import GooseCore
import Observation

/// The user's habits, for first-run setup and for editing them later (PRD S2). Every change goes
/// to the server and the list is read again afterwards, so positions, start days and archive
/// days are always the server's.
@MainActor @Observable
final class HabitsModel {
	enum State: Equatable {
		case loading
		case loaded
		/// The habits could not be read. Never shown as an empty list (constitution §8).
		case failed(String)
	}

	/// The most habits a day can have. The server's `max_habits` enforces it; this only disables
	/// the add button, so a user is not sent to a form the server will refuse.
	static let cap = 8

	private(set) var state: State
	/// Active and upcoming habits, in position order.
	private(set) var habits: [Habit]
	/// Why the last change did not happen, such as a refusal. Shown above the list.
	var problem: String?

	let environment: AppEnvironment
	private let now: @Sendable () -> Date

	init(environment: AppEnvironment, habits: [Habit]? = nil, now: @escaping @Sendable () -> Date = Date.init) {
		self.environment = environment
		self.now = now
		self.habits = habits ?? []
		state = habits == nil ? .loading : .loaded
	}

	/// Habits that are not archived. Archived ones still count today and leave tomorrow.
	var activeCount: Int { habits.count { $0.archivedFrom == nil } }
	var canAdd: Bool { state == .loaded && activeCount < Self.cap }

	/// The day the server is counting: the cached chase's date, or the device's date before the
	/// first chase exists.
	var today: LocalDate {
		if let chase = environment.chaseStore.snapshot?.chase { return chase.date }
		return LocalDate(rawValue: now().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))
	}

	/// What the user should know about when a habit counts, taken from the server's dates and
	/// from today's chase.
	func notice(for habit: Habit) -> String? {
		if habit.archivedFrom != nil { return "Archived from tomorrow. It still counts today." }
		if habit.effectiveFrom > today { return "Starts tomorrow" }
		if let chase = environment.chaseStore.snapshot?.chase, chase.date == today,
		   let counted = chase.habits.first(where: { $0.habitID == habit.id }), counted.target != habit.target {
			return "\(counted.target) \(habit.unit) today, \(habit.target) from tomorrow"
		}
		return nil
	}

	/// Reads the habits, and the chase that says which day is today.
	func load() async {
		await environment.chaseStore.refresh()
		do {
			habits = try await environment.habits.habits().sorted { $0.position < $1.position }
			environment.shared.setHabits(habits)
			state = .loaded
		} catch {
			let message = Self.message(for: error)
			if state == .loaded { problem = message } else { state = .failed(message) }
		}
	}

	/// Adds a habit. Throws the server's refusal for the form to show.
	func add(_ draft: HabitDraft) async throws {
		_ = try await environment.habits.createHabit(draft)
		problem = nil
		await load()
	}

	/// Changes a habit. Throws the server's refusal for the form to show.
	func update(_ habit: Habit, _ changes: HabitChanges) async throws {
		_ = try await environment.habits.updateHabit(id: habit.id, changes)
		problem = nil
		await load()
	}

	/// Moves one habit, as a list's drag does. The server renumbers the rest.
	func move(from source: IndexSet, to destination: Int) async {
		guard let from = source.first else { return }
		let position = destination > from ? destination - 1 : destination
		guard position != from else { return }
		await change { try await self.environment.habits.updateHabit(id: self.habits[from].id, HabitChanges(position: position)) }
	}

	func archive(_ habit: Habit) async {
		await change { try await self.environment.habits.archiveHabit(id: habit.id) }
	}

	private func change(_ write: () async throws -> Habit) async {
		do {
			_ = try await write()
			problem = nil
		} catch {
			problem = Self.message(for: error)
		}
		await load()
	}

	/// A sentence for a failure that is not about one field.
	static func message(for error: any Error) -> String {
		switch error as? APIError {
		case .invalid: "The server refused this change. A day can have at most \(cap) habits."
		case .notFound: "That habit is no longer there."
		case .transport, .credentialUnavailable: "Couldn't reach the server. Check your connection and try again."
		case .rateLimited: "Too many changes at once. Wait a moment and try again."
		default: "Something went wrong. Try again."
		}
	}
}
