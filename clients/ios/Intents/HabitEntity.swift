import AppIntents
import Foundation
import GooseCore

/// A habit, as the intents offer it. Its query reads the habits cached in the App Group, so it
/// answers without the network (TDD §6.8).
struct HabitEntity: AppEntity, Identifiable, Hashable {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
	static let defaultQuery = HabitQuery()

	let id: UUID
	let name: String
	let unit: String
	let chunk: Int

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)", subtitle: "\(chunk) \(unit) a tap")
	}

	/// The active habits: from the cached list, or from the cached chase when the list was never
	/// cached. Each habit in a chase carries its chunk, so either is enough.
	static func all(in environment: AppEnvironment) -> [HabitEntity] {
		let today = environment.shared.chaseSnapshot?.chase
		if let habits = environment.shared.habits {
			return habits
				.filter { habit in habit.archivedFrom.map { date in today.map { $0.date < date } ?? false } ?? true }
				.sorted { $0.position < $1.position }
				.map { HabitEntity(id: $0.id, name: $0.name, unit: $0.unit, chunk: $0.chunk) }
		}
		return (today?.habits ?? []).map { HabitEntity(id: $0.habitID, name: $0.name, unit: $0.unit, chunk: $0.chunk) }
	}
}

struct HabitQuery: EntityQuery {
	func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
		await habits().filter { identifiers.contains($0.id) }
	}

	func suggestedEntities() async throws -> [HabitEntity] {
		await habits()
	}

	@MainActor private func habits() -> [HabitEntity] {
		IntentEnvironment.make().map(HabitEntity.all(in:)) ?? []
	}
}
