import GooseCore
import GooseRig
import SwiftUI
import WidgetKit

// The two widgets' views (TDD §6.7). They take the family as a value, so the app's snapshot
// tests can draw every family without WidgetKit. The colours and type are the prototype's
// (docs/prototypes/src/04-app-screens.src.html).

enum WidgetStyle {
	static let ink = Color(red: 0x1D / 255, green: 0x1A / 255, blue: 0x2F / 255)
	static let paper = Color(red: 0xFF / 255, green: 0xFA / 255, blue: 0xF0 / 255)
	static let bread = Color(red: 0xE8 / 255, green: 0xAE / 255, blue: 0x4C / 255)
	static let good = Color(red: 0x17 / 255, green: 0x80 / 255, blue: 0x4A / 255)
	static let bad = Color(red: 0xD6 / 255, green: 0x3A / 255, blue: 0x1E / 255)
	static let display = "Shrikhand-Regular"
}

extension ShownChase {
	enum Tone { case plain, good, bad }

	var headline: String {
		switch state {
		case .complete: "Fed"
		case .caught: "Got you"
		case .running, .short: WidgetContent.steps(lead)
		}
	}

	var subline: String {
		if let age { return "Updated \(age) ago" }
		switch state {
		case .complete: return "The goose has the loaf"
		case .caught: return caughtAt.map { "at \($0)" } ?? "The goose got you"
		case .short: return "to spare at day's end"
		case .running: return "behind you"
		}
	}

	var tone: Tone {
		switch state {
		case .complete: .good
		case .caught: .bad
		case .running, .short: lead.rounded() <= 25 ? .bad : .plain
		}
	}

	var toneColor: Color {
		switch tone {
		case .plain: WidgetStyle.ink
		case .good: WidgetStyle.good
		case .bad: WidgetStyle.bad
		}
	}

	var pose: Pose {
		let stage = Stage(rawValue: min(max(stage, 0), 4)) ?? .goose
		return switch state {
		case .running: .running(lead: lead / 100, hour: hour, stage: stage)
		case .short: .short(lead: lead / 100, hour: hour, stage: stage)
		case .complete: .complete(lead: lead / 100, hour: hour, stage: stage)
		case .caught: .caught(hour: hour, stage: stage)
		}
	}
}

/// "Open Feed the Goose": signed out, or nothing cached yet.
struct OpenAppView: View {
	let shown: Shown
	let family: WidgetFamily

	var body: some View {
		switch family {
		case .accessoryCircular:
			Image(systemName: "bird").font(.title2).accessibilityLabel("Open Feed the Goose")
		case .accessoryRectangular:
			VStack(alignment: .leading) {
				Text("Feed the Goose").font(.headline)
				Text(shown == .signedOut ? "Open the app to sign in" : "Open the app").font(.caption)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		default:
			VStack(spacing: 6) {
				Text("Open Feed the Goose")
					.font(.custom(WidgetStyle.display, size: family == .systemSmall ? 20 : 24))
					.multilineTextAlignment(.center)
				Text(shown == .signedOut ? "Sign in to start the chase." : "Nothing to show yet.")
					.font(.system(size: 14, design: .rounded))
			}
			.foregroundStyle(WidgetStyle.ink)
			.padding()
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(WidgetStyle.paper)
		}
	}
}

/// The Chase widget: the scene, the lead and the stage.
struct ChaseWidgetView: View {
	let entry: ChaseEntry
	let family: WidgetFamily

	var body: some View {
		Group {
			if case let .chase(chase) = entry.shown {
				switch family {
				case .accessoryCircular: circular(chase)
				case .accessoryRectangular: rectangular(chase)
				default: system(chase)
				}
			} else {
				OpenAppView(shown: entry.shown, family: family)
			}
		}
		.widgetBackground(family)
	}

	private func system(_ chase: ShownChase) -> some View {
		let small = family == .systemSmall
		return VStack(spacing: 0) {
			SceneCanvas(pose: chase.pose)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.overlay(alignment: .topLeading) {
					if chase.age != nil {
						Text("Out of date")
							.font(.system(size: 11, weight: .bold, design: .rounded))
							.padding(.horizontal, 7).padding(.vertical, 3)
							.background(WidgetStyle.paper, in: Capsule())
							.foregroundStyle(WidgetStyle.ink)
							.padding(8)
					}
				}
			Rectangle().fill(WidgetStyle.ink).frame(height: 3)
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: 1) {
					Text(chase.headline)
						.font(.custom(WidgetStyle.display, size: small ? 20 : 24))
						.foregroundStyle(chase.toneColor)
						.lineLimit(1).minimumScaleFactor(0.6)
					Text(chase.subline)
						.font(.system(size: small ? 12 : 15, design: .rounded))
						.foregroundStyle(WidgetStyle.ink)
						.lineLimit(1).minimumScaleFactor(0.7)
				}
				Spacer(minLength: 4)
				if !small {
					Text(Stage(rawValue: chase.stage)?.name ?? "")
						.font(.system(size: 13, weight: .semibold, design: .rounded))
						.foregroundStyle(WidgetStyle.ink.opacity(0.6))
				}
			}
			.padding(.horizontal, small ? 12 : 16)
			.padding(.top, small ? 6 : 8)
			.padding(.bottom, small ? 10 : 12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(WidgetStyle.paper)
		}
		.accessibilityElement(children: .combine)
	}

	private func rectangular(_ chase: ShownChase) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(chase.headline).font(.headline).widgetAccentable()
			Text(chase.subline).font(.caption).lineLimit(1)
			if chase.state == .running || chase.state == .short {
				Gauge(value: min(max(chase.lead, 0), 100), in: 0 ... 100) {}
					.gaugeStyle(.accessoryLinear)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.accessibilityElement(children: .combine)
	}

	private func circular(_ chase: ShownChase) -> some View {
		Gauge(value: chase.state == .complete ? 100 : min(max(chase.lead, 0), 100), in: 0 ... 100) {
			Image(systemName: "bird")
		} currentValueLabel: {
			switch chase.state {
			case .complete: Image(systemName: "checkmark")
			case .caught: Image(systemName: "xmark")
			case .running, .short: Text("\(Int(chase.lead.rounded()))")
			}
		}
		.gaugeStyle(.accessoryCircular)
		.accessibilityLabel("\(chase.headline), \(chase.subline)")
	}
}

/// The Feed widget: a button for one chunk of each unfinished habit, or the day's result.
struct FeedWidgetView: View {
	let entry: ChaseEntry
	let family: WidgetFamily

	var body: some View {
		Group {
			if case let .chase(chase) = entry.shown {
				content(chase)
					.padding(family == .systemSmall ? 12 : 16)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
					.background(WidgetStyle.paper)
			} else {
				OpenAppView(shown: entry.shown, family: family)
			}
		}
		.widgetBackground(family)
	}

	@ViewBuilder
	private func content(_ chase: ShownChase) -> some View {
		let small = family == .systemSmall
		let buttons = chase.state == .running || chase.state == .short ? Array(chase.open.prefix(small ? 1 : 3)) : []
		VStack(alignment: .leading, spacing: small ? 8 : 10) {
			VStack(alignment: .leading, spacing: 1) {
				Text(chase.headline)
					.font(.custom(WidgetStyle.display, size: small ? 20 : 24))
					.foregroundStyle(chase.toneColor)
					.lineLimit(1).minimumScaleFactor(0.6)
				Text(chase.subline)
					.font(.system(size: small ? 12 : 15, design: .rounded))
					.foregroundStyle(WidgetStyle.ink)
					.lineLimit(1).minimumScaleFactor(0.7)
			}
			Spacer(minLength: 0)
			if buttons.isEmpty {
				Text(chase.state == .caught ? "A new chase starts tomorrow." : "Nothing left to log today.")
					.font(.system(size: small ? 12 : 14, design: .rounded))
					.foregroundStyle(WidgetStyle.ink.opacity(0.7))
			} else if small {
				ForEach(buttons) { FeedButton(habit: $0) }
			} else {
				HStack(spacing: 6) {
					ForEach(buttons) { FeedButton(habit: $0) }
				}
			}
		}
	}
}

/// "+10 pushups": logs one chunk of a habit from the widget, without opening the app.
struct FeedButton: View {
	let habit: ChaseHabit

	var body: some View {
		Button(intent: LogFromWidgetIntent(habitID: habit.habitID, amount: habit.chunk)) {
			Text("+\(habit.chunk) \(habit.name.lowercased())")
				.font(.system(size: 13, weight: .bold, design: .rounded))
				.lineLimit(1).minimumScaleFactor(0.7)
				.foregroundStyle(WidgetStyle.ink)
				.padding(.horizontal, 8)
				.frame(maxWidth: .infinity, minHeight: 40)
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		// On the button, not its label: a plain button may lay its label out wider than it
		// draws it, which cut the capsule's ends.
		.background(WidgetStyle.bread, in: Capsule())
		.overlay(Capsule().strokeBorder(WidgetStyle.ink, lineWidth: 2.5))
		.clipShape(Capsule())
		.accessibilityLabel("+\(habit.chunk) \(habit.name.lowercased())")
		.accessibilityHint("Logs \(habit.chunk) \(habit.unit) of \(habit.name)")
	}
}

private extension View {
	/// The paper behind the Home Screen families; the system's material behind the Lock
	/// Screen's.
	@ViewBuilder
	func widgetBackground(_ family: WidgetFamily) -> some View {
		switch family {
		case .accessoryCircular, .accessoryRectangular, .accessoryInline:
			containerBackground(for: .widget) { AccessoryWidgetBackground() }
		default:
			containerBackground(WidgetStyle.paper, for: .widget)
		}
	}
}
