import GooseCore
import GooseRig
import SwiftUI

/// Today (TDD §6.5, PRD S3 to S7, S10, S11): the scene, the headline and its line, the streak
/// and stage, a row per habit with its log buttons, and the logs waiting to be sent.
struct TodayView: View {
	@State private var model: TodayModel
	@Environment(\.scenePhase) private var scenePhase

	init(environment: AppEnvironment) {
		#if DEBUG
			let environment = TodayScript.environment(replacing: environment) ?? environment
		#endif
		_model = State(initialValue: TodayModel(environment: environment))
	}

	/// For snapshots and tests: a model built by the caller.
	init(model: TodayModel) {
		_model = State(initialValue: model)
	}

	var body: some View {
		Group {
			switch model.state {
			case .loading:
				ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
					.accessibilityIdentifier("today.loading")
			case .noChase:
				ContentUnavailableView(
					"No chase today",
					systemImage: "calendar",
					description: Text("Your habits start with tomorrow's chase.")
				)
				.accessibilityIdentifier("today.noChase")
			case let .unavailable(error):
				ContentUnavailableView {
					Label("Couldn't load the chase", systemImage: "wifi.exclamationmark")
				} description: {
					Text(error == .credentialUnavailable ? "Unlock your phone and try again." : "Check your connection and try again.")
				} actions: {
					Button("Try again") { Task { await model.refresh() } }
						.buttonStyle(.borderedProminent)
				}
				.accessibilityIdentifier("today.unavailable")
			case let .showing(snapshot):
				chase(snapshot)
			}
		}
		.background(TodayPalette.paper)
		.toolbar(.hidden, for: .navigationBar)
		.task { await model.run() }
		.onChange(of: scenePhase) { _, phase in
			if phase == .active { Task { await model.refresh() } }
		}
	}

	private func chase(_ snapshot: ChaseSnapshot) -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				// Redraw every second so the lead counts down between fetches.
				TimelineView(.periodic(from: .now, by: 1)) { _ in
					let date = model.now()
					VStack(alignment: .leading, spacing: 0) {
						TodayScene(snapshot: snapshot, playing: model.playing, date: date, timeZone: model.timeZone) { model.clipFinished($0) }
						Rectangle().fill(TodayPalette.ink).frame(height: 3)
						readout(snapshot, at: date)
					}
				}
				Rectangle().fill(TodayPalette.rule).frame(height: 1)
				habits(snapshot.chase)
				if !model.pending.isEmpty {
					waiting
				}
			}
			.foregroundStyle(TodayPalette.ink)
		}
		.scrollBounceBehavior(.basedOnSize)
		.ignoresSafeArea(edges: .top)
		.refreshable { await model.refresh() }
	}

	// MARK: - The readout

	private func readout(_ snapshot: ChaseSnapshot, at date: Date) -> some View {
		let readout = TodayText.readout(snapshot, at: date, line: model.line, timeZone: model.timeZone)
		let stage = Stage(rawValue: snapshot.chase.streak.stage) ?? .gosling
		// On a finished day the headline says what happened; the line for a log that needs to be
		// seen, such as a queued one, follows it.
		let extra = snapshot.chase.state == .running ? nil : model.line.flatMap(TodayText.text)
		return VStack(alignment: .leading, spacing: 10) {
			if snapshot.isOutOfDate {
				Label(TodayText.outOfDate(snapshot, at: date), systemImage: "clock.badge.exclamationmark")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(TodayPalette.warning)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(TodayPalette.warningFill, in: RoundedRectangle(cornerRadius: 12))
					.accessibilityIdentifier("today.outOfDate")
			}
			Text("\(TodayText.streakText(snapshot.chase.streak.completeDays)) · \(stage.name)")
				.font(.subheadline.weight(.bold))
				.padding(.horizontal, 12)
				.padding(.vertical, 4)
				.background {
					RoundedRectangle(cornerRadius: 10)
						.fill(TodayPalette.bread)
						.strokeBorder(TodayPalette.ink, lineWidth: 2)
				}
				.accessibilityLabel("\(TodayText.streakText(snapshot.chase.streak.completeDays)). The goose is a \(stage.name.lowercased()).")
				.accessibilityIdentifier("today.streak")
			Text(readout.head)
				.font(.custom("Shrikhand-Regular", size: 30, relativeTo: .largeTitle))
				.foregroundStyle(TodayPalette.tone(readout.tone))
				.accessibilityAddTraits(.isHeader)
				.accessibilityIdentifier("today.headline")
			VStack(alignment: .leading, spacing: 6) {
				Text(readout.sub)
					.accessibilityIdentifier("today.line")
				if let extra {
					Text(extra).accessibilityIdentifier("today.extra")
				}
				if model.undoable != nil {
					Button("Undo") { Task { await model.undo() } }
						.font(.body.weight(.bold))
						.underline()
						.accessibilityLabel("Undo the last log")
						.accessibilityIdentifier("today.undo")
				}
			}
			.font(.body)
		}
		.padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .contain)
	}

	// MARK: - Habits

	private func habits(_ chase: Chase) -> some View {
		VStack(spacing: 0) {
			ForEach(chase.habits) { habit in
				HabitRow(habit: habit, state: chase.state) { amount in
					await model.log(habit, amount: amount)
				}
				if habit.id != chase.habits.last?.id {
					Rectangle().fill(TodayPalette.rule).frame(height: 1).padding(.horizontal, 20)
				}
			}
		}
		.padding(.bottom, 12)
	}

	private var waiting: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Waiting to send").font(.headline)
			ForEach(model.pending) { request in
				let habit = model.habit(request.habitID)
				Text("\(request.amount ?? habit?.chunk ?? 0) \(habit?.unit ?? "") of \(habit?.name ?? "a habit") at \(TodayText.clock(request.loggedAt, model.timeZone))")
					.accessibilityIdentifier("today.waiting.row")
			}
			Text("They'll count when you're back online, at the time you logged them.")
				.font(.footnote)
				.foregroundStyle(TodayPalette.secondary)
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(TodayPalette.warningFill, in: RoundedRectangle(cornerRadius: 14))
		.padding(.horizontal, 20)
		.padding(.bottom, 24)
		.accessibilityElement(children: .combine)
		.accessibilityIdentifier("today.waiting")
	}
}

/// One habit: its progress, a chunk button, a finish button, and another amount on demand.
struct HabitRow: View {
	let habit: ChaseHabit
	let state: ChaseState
	let log: (Int) async -> Void
	@State private var otherAmount: Int?
	@Environment(\.dynamicTypeSize) private var typeSize

	/// Side by side, or stacked at the accessibility type sizes.
	private var layout: AnyLayout {
		typeSize.isAccessibilitySize
			? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
			: AnyLayout(HStackLayout(spacing: 12))
	}

	private var remaining: Int { max(0, habit.target - habit.logged) }
	/// A caught day takes no more logs. A short day still does, during the night (PRD S7).
	private var canLog: Bool { state != .caught }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			layout {
				info
				if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
				actions
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			if let amount = otherAmount, !habit.done, canLog {
				other(amount)
			}
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 14)
	}

	/// The name and progress. Tapping them opens another amount, while the habit takes logs.
	@ViewBuilder private var info: some View {
		let label = VStack(alignment: .leading, spacing: 2) {
			Text(habit.name).font(.title3.weight(.bold))
			Text("\(habit.logged) of \(habit.target) \(habit.unit)")
		}
		.multilineTextAlignment(.leading)
		// Wraps instead of truncating at large type sizes.
		.fixedSize(horizontal: false, vertical: true)
		.contentShape(Rectangle())
		if habit.done || !canLog {
			label
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("\(habit.name), \(habit.logged) of \(habit.target) \(habit.unit)")
		} else {
			Button { otherAmount = otherAmount == nil ? habit.chunk : nil } label: { label }
				.buttonStyle(.plain)
				.accessibilityLabel("\(habit.name), \(habit.logged) of \(habit.target) \(habit.unit)")
				.accessibilityHint("Shows a field to log another amount")
				.accessibilityIdentifier("today.name.\(habit.name)")
		}
	}

	@ViewBuilder private var actions: some View {
		if habit.done {
			Text("Done")
				.font(.headline)
				.foregroundStyle(TodayPalette.good)
				.fixedSize()
				.accessibilityLabel("\(habit.name) done")
		} else {
			HStack(spacing: 10) {
				if remaining > habit.chunk {
					Button("+\(habit.chunk)") { Task { await log(habit.chunk) } }
						.buttonStyle(LogButtonStyle(fill: .white))
						.accessibilityLabel("Log \(habit.chunk) \(habit.unit) of \(habit.name)")
						.accessibilityIdentifier("today.chunk.\(habit.name)")
				}
				Button("Finish \(remaining)") { Task { await log(remaining) } }
					.buttonStyle(LogButtonStyle(fill: TodayPalette.bread))
					.accessibilityLabel("Finish \(habit.name): log the remaining \(remaining) \(habit.unit)")
					.accessibilityIdentifier("today.finish.\(habit.name)")
			}
			.disabled(!canLog)
		}
	}

	private func other(_ amount: Int) -> some View {
		let value = Binding { otherAmount ?? amount } set: { otherAmount = $0 }
		return layout {
			stepper(value)
			if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
			logOther(amount)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(TodayPalette.paperDeep, in: RoundedRectangle(cornerRadius: 14))
	}

	/// The prototype's "Other amount": one less, the amount, one more.
	private func stepper(_ value: Binding<Int>) -> some View {
		HStack(spacing: 10) {
			Text("Other amount").font(.body.weight(.semibold))
			step("minus", "One less", by: -1, value, disabled: value.wrappedValue <= 1)
			Text("\(value.wrappedValue)")
				.font(.title3.weight(.bold).monospacedDigit())
				.frame(minWidth: 36)
				.accessibilityIdentifier("today.otherAmount.\(habit.name)")
			step("plus", "One more", by: 1, value, disabled: value.wrappedValue >= 9999)
		}
		.fixedSize()
	}

	private func step(_ symbol: String, _ label: String, by delta: Int, _ value: Binding<Int>, disabled: Bool) -> some View {
		Button { value.wrappedValue += delta } label: {
			Image(systemName: symbol).font(.body.weight(.bold)).frame(width: 44, height: 44)
		}
		.foregroundStyle(TodayPalette.ink)
		.background(Circle().fill(.white))
		.overlay(Circle().strokeBorder(TodayPalette.ink, lineWidth: 2))
		.disabled(disabled)
		.accessibilityLabel(label)
	}

	private func logOther(_ amount: Int) -> some View {
		Button("Log \(amount)") {
			otherAmount = nil
			Task { await log(amount) }
		}
		.buttonStyle(LogButtonStyle(fill: TodayPalette.bread))
		.accessibilityHint("Logs \(amount) \(habit.unit) of \(habit.name)")
		.accessibilityIdentifier("today.logOther.\(habit.name)")
	}
}

/// The prototype's chunky buttons: an ink outline with a hard shadow under it.
struct LogButtonStyle: ButtonStyle {
	let fill: Color
	@Environment(\.isEnabled) private var isEnabled

	func makeBody(configuration: Configuration) -> some View {
		let pressed = configuration.isPressed
		let edge = isEnabled ? TodayPalette.ink : TodayPalette.disabled
		configuration.label
			.font(.headline)
			.lineLimit(1)
			.fixedSize()
			.foregroundStyle(isEnabled ? TodayPalette.ink : TodayPalette.disabledText)
			.padding(.horizontal, 18)
			.frame(minHeight: 44)
			// Opaque, so the shadow under the button does not show through a faded fill.
			.background {
				RoundedRectangle(cornerRadius: 14).fill(TodayPalette.paper)
				RoundedRectangle(cornerRadius: 14).fill(isEnabled ? fill : fill.opacity(0.4))
			}
			.overlay(RoundedRectangle(cornerRadius: 14).stroke(edge, lineWidth: 2.5))
			.background(RoundedRectangle(cornerRadius: 14).fill(edge).offset(y: pressed ? 0 : 4))
			.offset(y: pressed ? 4 : 0)
			.padding(.bottom, 4)
	}
}

enum TodayPalette {
	static let ink = Color(red: 0x1d / 255, green: 0x1a / 255, blue: 0x2f / 255)
	static let paper = Color(red: 0xfd / 255, green: 0xf8 / 255, blue: 0xee / 255)
	static let paperDeep = Color(red: 0xf4 / 255, green: 0xec / 255, blue: 0xda / 255)
	static let bread = Color(red: 0xe8 / 255, green: 0xae / 255, blue: 0x4c / 255)
	static let rule = Color(red: 0xd9 / 255, green: 0xd2 / 255, blue: 0xc4 / 255)
	static let good = Color(red: 0x17 / 255, green: 0x80 / 255, blue: 0x4a / 255)
	static let bad = Color(red: 0xc2 / 255, green: 0x33 / 255, blue: 0x17 / 255)
	static let warning = Color(red: 0x8a / 255, green: 0x4b / 255, blue: 0x00 / 255)
	static let warningFill = Color(red: 0xfb / 255, green: 0xe8 / 255, blue: 0xc8 / 255)
	static let secondary = Color(red: 0x55 / 255, green: 0x50 / 255, blue: 0x66 / 255)
	static let disabled = Color(red: 0x9a / 255, green: 0x95 / 255, blue: 0x9e / 255)
	static let disabledText = Color(red: 0x6e / 255, green: 0x69 / 255, blue: 0x75 / 255)

	static func tone(_ tone: Readout.Tone) -> Color {
		switch tone {
		case .plain: ink
		case .low, .bad: bad
		case .good: good
		}
	}
}
