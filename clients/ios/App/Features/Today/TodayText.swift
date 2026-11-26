import Foundation
import GooseCore

/// The goose's words for a chase: the headline and the line under it (PRD S3 to S7, S10). They
/// describe what the server said; none of them works out a state.
struct Readout: Equatable {
	enum Tone: Equatable { case plain, low, good, bad }

	var head: String
	var sub: String
	var tone: Tone
}

enum TodayText {
	/// At or below this many steps the headline turns red to warn the user (PRD S3). A display
	/// choice, from the prototype, not a rule of the chase.
	static let lowLead = 25.0

	static func readout(_ snapshot: ChaseSnapshot, at date: Date, line: TodayModel.Line?, timeZone: TimeZone) -> Readout {
		let chase = snapshot.chase
		let lead = snapshot.clock.lead(at: date)
		let time = { (instant: Date) in clock(snapshot.clock.deviceTime(of: instant), timeZone) }
		switch chase.state {
		case .complete:
			return Readout(
				head: "The goose is fed",
				sub: "It has the whole loaf, and sleeps until \(time(chase.nextDayStartsAt)).",
				tone: .good
			)
		case .caught:
			let when = chase.caughtAt.map { "Caught at \(time($0))." } ?? "Caught."
			return Readout(
				head: "The goose got you",
				sub: "\(when)\(owedSentence(chase)) A new chase starts at \(time(chase.nextDayStartsAt)).",
				tone: .bad
			)
		case .short:
			let left = steps(chase.lead)
			return Readout(
				head: "\(stepsPhrase(left)) to spare",
				sub: "The day ended at \(time(chase.dayEndsAt)).\(owedSentence(chase)) Logs until \(time(chase.nextDayStartsAt)) still count for it.",
				tone: .plain
			)
		case .running:
			let shown = steps(lead)
			let head = shown == 0 ? "The goose is right behind you" : "\(stepsPhrase(shown)) behind you"
			let sub = line.flatMap(text) ?? "It's \(clock(date, timeZone)). The goose gains about \(stepsPhrase(steps(chase.stepsPerHour))) an hour."
			return Readout(head: head, sub: sub, tone: lead <= lowLead ? .low : .plain)
		}
	}

	/// The line for what the user just did, or nil when the headline already says it.
	static func text(_ line: TodayModel.Line) -> String? {
		switch line {
		case let .logged(amount, unit, earned, kind):
			switch kind {
			case .gain where steps(earned) == 0:
				return "\(amount) \(unit) logged. That habit was already done, so the goose gets nothing more."
			case .gain:
				return "\(amount) \(unit) logged. The goose stops for the crust and you gain \(stepsPhrase(steps(earned)))."
			case .complete:
				return nil
			case .caught:
				return "\(amount) \(unit) logged, but the goose had already caught you."
			case .undone:
				return nil
			}
		case let .undone(amount, unit, earned):
			return "Took back \(amount) \(unit) and the \(stepsPhrase(steps(earned))) they earned."
		case let .queued(amount, unit):
			return "\(amount) \(unit) logged, they'll count when you're back online."
		case let .tooLate(amount, unit):
			return "\(amount) \(unit) arrived after the day settled, so they didn't count."
		case let .rejected(amount, unit):
			return "\(amount) \(unit) weren't logged: the server refused them."
		case let .notSaved(amount, unit):
			return "\(amount) \(unit) weren't saved. Try again."
		case let .sent(count):
			return count == 1 ? "Your waiting log went through." : "Your \(count) waiting logs went through."
		case let .undoFailed(tooLate):
			return tooLate ? "Too late to undo: the day has settled." : "Couldn't undo. Check your connection and try again."
		}
	}

	/// How old an out-of-date chase is, such as "Out of date: last updated 12 min ago".
	static func outOfDate(_ snapshot: ChaseSnapshot, at date: Date) -> String {
		let minutes = Int(date.timeIntervalSince(snapshot.receivedAt) / 60)
		let age = switch minutes {
		case ..<1: "just now"
		case ..<60: "\(minutes) min ago"
		default: "\(minutes / 60) h ago"
		}
		return "Out of date: last updated \(age). Pull to refresh."
	}

	/// The scene in words, for VoiceOver.
	static func sceneLabel(_ snapshot: ChaseSnapshot, at date: Date, stageName: String) -> String {
		let chase = snapshot.chase
		let who = "A \(stageName.lowercased())"
		let streak = streakText(chase.streak.completeDays)
		switch chase.state {
		case .running: return "\(who) is chasing you, \(stepsPhrase(steps(snapshot.clock.lead(at: date)))) behind. \(streak)."
		case .short: return "The day is over. \(who) stopped \(stepsPhrase(steps(chase.lead))) behind you. \(streak)."
		case .complete: return "\(who) is asleep, fed. \(streak)."
		case .caught: return "\(who) has caught you. \(streak)."
		}
	}

	static func streakText(_ days: Int) -> String {
		days == 0 ? "No streak yet" : "\(days)-day streak"
	}

	// MARK: - Pieces

	/// Steps as the user sees them: whole steps.
	static func steps(_ value: Double) -> Int { Int(value.rounded()) }

	static func stepsPhrase(_ count: Int) -> String { count == 1 ? "1 step" : "\(count) steps" }

	static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
		var style = Date.FormatStyle(date: .omitted, time: .shortened)
		style.timeZone = timeZone
		return date.formatted(style)
	}

	/// " You still owed 30 reps and 20 pages." for the habits left unfinished.
	static func owedSentence(_ chase: Chase) -> String {
		let owed = chase.habits.filter { !$0.done }.map { "\(max(0, $0.target - $0.logged)) \($0.unit)" }
		guard !owed.isEmpty else { return "" }
		return " You still owed \(owed.formatted(.list(type: .and)))."
	}
}
