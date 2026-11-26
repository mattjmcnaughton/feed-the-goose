import GooseCore
import SwiftUI

/// The habits as a list that adds, edits, reorders and archives them. `HabitSetupView` and
/// `HabitsView` both show it, with their own header.
struct HabitList<Header: View>: View {
	@Bindable var model: HabitsModel
	@ViewBuilder var header: Header

	@State private var form: HabitFormModel?
	@State private var archiving: Habit?
	@Environment(\.editMode) private var editMode

	var body: some View {
		List {
			header
			if let problem = model.problem {
				Section {
					Label(problem, systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(SignInPalette.problem)
						.accessibilityIdentifier("habits.problem")
				}
			}
			switch model.state {
			case .loading:
				Section { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("habits.loading") }
			case let .failed(message):
				Section {
					Label(message, systemImage: "wifi.exclamationmark").accessibilityIdentifier("habits.failed")
					Button("Try again") { Task { await model.load() } }
				}
			case .loaded:
				habitsSection
				addSection
			}
		}
		.refreshable { await model.load() }
		.sheet(item: Binding(get: { form.map(FormItem.init) }, set: { form = $0?.model })) { item in
			NavigationStack { HabitFormView(model: item.model) }
		}
		.confirmationDialog(
			"Archive \(archiving?.name ?? "this habit")?",
			isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }),
			titleVisibility: .visible,
			presenting: archiving
		) { habit in
			Button("Archive from tomorrow", role: .destructive) { Task { await model.archive(habit) } }
		} message: { _ in
			Text("It still counts today, and leaves your chase tomorrow.")
		}
	}

	@ViewBuilder private var habitsSection: some View {
		Section {
			if model.habits.isEmpty {
				Text("No habits yet. Add the first one below.")
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("habits.empty")
			}
			ForEach(model.habits) { habit in
				Button { edit(habit) } label: { HabitRow(habit: habit, notice: model.notice(for: habit)) }
					.buttonStyle(.plain)
					.disabled(habit.archivedFrom != nil)
					.accessibilityIdentifier("habit.\(habit.name)")
					.swipeActions {
						if habit.archivedFrom == nil {
							Button("Archive") { archiving = habit }.tint(SignInPalette.problem)
						}
					}
					.contextMenu {
						if habit.archivedFrom == nil {
							Button("Edit", systemImage: "pencil") { edit(habit) }
							Button("Archive", systemImage: "archivebox", role: .destructive) { archiving = habit }
						}
					}
			}
			.onMove { source, destination in Task { await model.move(from: source, to: destination) } }
		} header: {
			HStack {
				Text("Your habits · \(model.activeCount) of \(HabitsModel.cap)")
				Spacer()
				if model.habits.count > 1 { EditButton().accessibilityIdentifier("habits.reorder") }
			}
		}
	}

	@ViewBuilder private var addSection: some View {
		Section {
			Button {
				form = HabitFormModel { [model] output in
					if case let .create(draft) = output { try await model.add(draft) }
				}
			} label: {
				Label("Add a habit", systemImage: "plus.circle.fill").font(.headline)
			}
			.disabled(!model.canAdd)
			.accessibilityIdentifier("habits.add")
		} footer: {
			if !model.canAdd {
				Text("A day can have at most \(HabitsModel.cap) habits. Archive one to make room.")
					.accessibilityIdentifier("habits.full")
			}
		}
	}

	private func edit(_ habit: Habit) {
		guard editMode?.wrappedValue.isEditing != true else { return }
		form = HabitFormModel(editing: habit) { [model] output in
			if case let .update(habit, changes) = output { try await model.update(habit, changes) }
		}
	}
}

/// Wraps the form's model so `sheet(item:)` can present it.
private struct FormItem: Identifiable {
	let model: HabitFormModel
	var id: ObjectIdentifier { ObjectIdentifier(model) }
}

/// One habit: its name, its target and chunk, and when it counts.
struct HabitRow: View {
	let habit: Habit
	let notice: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(habit.name).font(.headline)
				.strikethrough(habit.archivedFrom != nil)
			Text("\(habit.target) \(habit.unit) a day · +\(habit.chunk) a tap")
				.font(.subheadline)
				.foregroundStyle(.secondary)
			if let notice {
				Label(notice, systemImage: "calendar.badge.clock")
					.font(.footnote.weight(.semibold))
					.foregroundStyle(SignInPalette.ink)
					.accessibilityIdentifier("habit.\(habit.name).notice")
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.contentShape(Rectangle())
		.padding(.vertical, 2)
		.accessibilityElement(children: .combine)
	}
}
