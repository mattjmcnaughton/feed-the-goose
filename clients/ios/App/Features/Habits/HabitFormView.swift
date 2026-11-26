import GooseCore
import SwiftUI

/// Adds a habit or edits one: a name, a unit, a daily target and the chunk one tap logs.
struct HabitFormView: View {
	@Bindable var model: HabitFormModel
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		Form {
			if let problem = model.problem {
				Section {
					Label(problem, systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(SignInPalette.problem)
						.accessibilityIdentifier("habitForm.problem")
				}
			}
			Section {
				field(.name, "Name", prompt: "Pushups", text: $model.name)
				field(.unit, "Unit", prompt: "reps", text: $model.unit)
			}
			Section {
				field(.target, "Daily target", prompt: "50", text: $model.target, number: true)
				field(.chunk, "One tap logs", prompt: "10", text: $model.chunk, number: true)
			} footer: {
				if model.changesTarget {
					Text("A new target counts from tomorrow. Today keeps \(model.original?.target ?? 0).")
						.accessibilityIdentifier("habitForm.targetNotice")
				} else {
					Text("The chunk is what a widget button or a tap on Today logs.")
				}
			}
		}
		.navigationTitle(model.title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") { dismiss() }.accessibilityIdentifier("habitForm.cancel")
			}
			ToolbarItem(placement: .confirmationAction) {
				if model.state == .saving {
					ProgressView()
				} else {
					Button("Save") { Task { if await model.submit() { dismiss() } } }
						.accessibilityIdentifier("habitForm.save")
				}
			}
		}
		.interactiveDismissDisabled(model.state == .saving)
	}

	private func field(
		_ field: HabitFormModel.Field, _ label: String, prompt: String, text: Binding<String>, number: Bool = false
	) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			LabeledContent(label) {
				TextField(label, text: text, prompt: Text(verbatim: prompt))
					.multilineTextAlignment(.trailing)
					.keyboardType(number ? .numberPad : .default)
					.textInputAutocapitalization(field == .name ? .words : .never)
					.autocorrectionDisabled()
					.accessibilityIdentifier("habitForm.\(field.rawValue)")
			}
			if let error = model.errors[field] {
				Text(error)
					.font(.footnote)
					.foregroundStyle(SignInPalette.problem)
					.accessibilityIdentifier("habitForm.\(field.rawValue).error")
			}
		}
	}
}
