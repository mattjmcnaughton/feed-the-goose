import SwiftUI

/// Edits when the day starts and ends and its time zone. Saving sends them to the server,
/// which holds them until tomorrow; the form shows the server's refusal when there is one.
struct DayEditorView: View {
	let model: SettingsModel
	@Environment(\.dismiss) private var dismiss
	@State private var start: String
	@State private var end: String
	@State private var timeZone: String

	/// Starts from the hours tomorrow will use, unless `start` and `end` are given.
	init(model: SettingsModel, start: String? = nil, end: String? = nil) {
		self.model = model
		let upcoming = model.upcoming ?? ("UTC", "06:00", "00:00")
		_start = State(initialValue: start ?? upcoming.dayStart)
		_end = State(initialValue: end ?? upcoming.dayEnd)
		_timeZone = State(initialValue: upcoming.timeZone)
	}

	var body: some View {
		Form {
			Section {
				Picker("Starts", selection: $start) {
					ForEach(DayWindow.options(including: start), id: \.self) { Text(DayWindow.label($0)).tag($0) }
				}
				.accessibilityIdentifier("day.start")
				Picker("Ends", selection: $end) {
					ForEach(DayWindow.options(including: end), id: \.self) { Text(DayWindow.label($0)).tag($0) }
				}
				.accessibilityIdentifier("day.end")
				Picker("Time zone", selection: $timeZone) {
					ForEach(Self.zones(including: timeZone), id: \.self) { Text($0).tag($0) }
				}
				.pickerStyle(.navigationLink)
				.accessibilityIdentifier("day.timeZone")
			} footer: {
				if let hours = DayWindow.hours(start: start, end: end) {
					Text("This day is \(DayWindow.describe(hours)) long. It must be 8 to 22 hours. Changes start tomorrow; today keeps its hours.")
				}
			}
			if let problem = model.dayProblem {
				Section {
					Label(problem, systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.red)
						.accessibilityIdentifier("day.problem")
				}
			}
		}
		.navigationTitle("Your day")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") {
					model.dayProblem = nil
					dismiss()
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") {
					Task {
						if await model.saveDay(start: start, end: end, timeZone: timeZone) { dismiss() }
					}
				}
				.disabled(model.working)
				.accessibilityIdentifier("day.save")
			}
		}
	}

	static func zones(including zone: String) -> [String] {
		var all = Set(TimeZone.knownTimeZoneIdentifiers)
		all.insert(zone)
		return all.sorted()
	}
}
