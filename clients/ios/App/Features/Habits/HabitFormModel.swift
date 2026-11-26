import Foundation
import GooseCore
import Observation

/// The form that adds a habit or edits one. Its checks mirror the server's (a name and a unit
/// that are not empty, a target and a chunk above 0), and a refusal from the server lands on
/// the field it names.
@MainActor @Observable
final class HabitFormModel {
	enum Field: String, CaseIterable, Hashable {
		case name, unit, target, chunk
	}

	enum State: Equatable {
		case editing
		case saving
	}

	var name: String
	var unit: String
	var target: String
	var chunk: String
	private(set) var state: State = .editing
	private(set) var errors: [Field: String]
	/// A refusal or failure that is not about one field.
	private(set) var problem: String?

	/// The habit being edited, or nil for a new one.
	let original: Habit?
	private let save: (HabitFormModel.Output) async throws -> Void

	enum Output: Equatable {
		case create(HabitDraft)
		case update(Habit, HabitChanges)
	}

	init(
		editing original: Habit? = nil,
		errors: [Field: String] = [:],
		problem: String? = nil,
		save: @escaping (Output) async throws -> Void
	) {
		self.original = original
		name = original?.name ?? ""
		unit = original?.unit ?? ""
		target = original.map { String($0.target) } ?? ""
		chunk = original.map { String($0.chunk) } ?? ""
		self.errors = errors
		self.problem = problem
		self.save = save
	}

	var title: String { original == nil ? "New habit" : "Edit habit" }

	/// True when an edit changes the target, which counts from tomorrow.
	var changesTarget: Bool {
		guard let original, let value = Int(target.trimmingCharacters(in: .whitespaces)) else { return false }
		return value != original.target
	}

	/// Checks the fields, then saves. Returns true when the habit was saved and the form can
	/// close.
	func submit() async -> Bool {
		guard state == .editing else { return false }
		problem = nil
		guard let output = validate() else { return false }
		if case let .update(_, changes) = output, changes == HabitChanges() { return true }
		state = .saving
		defer { state = .editing }
		do {
			try await save(output)
			return true
		} catch let APIError.invalid(fieldErrors) where !fieldErrors.isEmpty {
			for error in fieldErrors {
				if let field = Field(rawValue: error.field) { errors[field] = error.message } else { problem = error.message }
			}
		} catch {
			problem = HabitsModel.message(for: error)
		}
		return false
	}

	/// The request the fields make, or nil with `errors` set.
	private func validate() -> Output? {
		errors = [:]
		let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
		if name.isEmpty { errors[.name] = "Give the habit a name." }
		if unit.isEmpty { errors[.unit] = "Give a unit, such as reps or minutes." }
		let target = Self.count(target, field: .target, into: &errors)
		let chunk = Self.count(chunk, field: .chunk, into: &errors)
		guard errors.isEmpty, let target, let chunk else { return nil }
		guard let original else { return .create(HabitDraft(name: name, unit: unit, target: target, chunk: chunk)) }
		return .update(original, HabitChanges(
			name: name == original.name ? nil : name,
			unit: unit == original.unit ? nil : unit,
			target: target == original.target ? nil : target,
			chunk: chunk == original.chunk ? nil : chunk
		))
	}

	private static func count(_ text: String, field: Field, into errors: inout [Field: String]) -> Int? {
		guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0 else {
			errors[field] = "Enter a whole number above 0."
			return nil
		}
		return value
	}
}
