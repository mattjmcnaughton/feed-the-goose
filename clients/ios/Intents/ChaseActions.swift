import Foundation
import GooseCore

/// What the intents do, given an environment, so a widget tap, a Shortcuts action and a test
/// run the same code. Every log goes through `LogQueue` and every chase through `ChaseStore`
/// (TDD §6.8). Each returns the sentence the intent replies with.
@MainActor
enum ChaseActions {
	static let signedOut = "Open Feed the Goose and sign in first."
	static let unavailable = "Feed the Goose isn't set up on this phone yet. Open the app first."

	/// Logs `amount` of a habit, or its chunk when nil.
	static func log(habitID: UUID, amount: Int?, source: LogSource, in environment: AppEnvironment) async -> String {
		guard isSignedIn(environment) else { return signedOut }
		let name = habitName(habitID, in: environment)
		switch await environment.logQueue.log(habitID: habitID, amount: amount, source: source) {
		case let .logged(_, result, _):
			let unit = result.chase.habits.first { $0.habitID == habitID }?.unit ?? ""
			return "Logged \(result.log.amount) \(unit) of \(name). \(standing(result.chase, lead: result.chase.lead))"
		case .queued:
			return "Saved. \(name) will count when your phone is back online."
		case .tooLate:
			return "That day has ended, so the log was too late to count."
		case .rejected:
			return "Feed the Goose couldn't log that. Check the habit in the app."
		case .notSaved:
			return "That wasn't logged. Try again."
		}
	}

	/// Undoes the newest log of the current day that is not undone yet.
	static func undoLast(in environment: AppEnvironment) async -> String {
		guard isSignedIn(environment) else { return signedOut }
		do {
			var date = environment.chaseStore.snapshot?.chase.date
			if date == nil { date = try await environment.chase.today().date }
			guard let date else { return "There's nothing to undo today." }
			guard let last = try await environment.logs.logs(on: date).first(where: { $0.undoneAt == nil }) else {
				return "There's nothing to undo today."
			}
			let result = try await environment.logs.undoLog(id: last.id)
			environment.chaseStore.receive(result)
			let habit = result.chase.habits.first { $0.habitID == last.habitID }
			return "Undid \(last.amount) \(habit?.unit ?? "") of \(habit?.name ?? "a habit"). \(standing(result.chase, lead: result.chase.lead))"
		} catch APIError.daySettled {
			return "That day has ended, so its logs can't be undone."
		} catch {
			return "Couldn't reach Feed the Goose, so nothing was undone."
		}
	}

	/// Fetches the chase and says how it stands. A chase that could not be fetched is described
	/// with its age, never as current (constitution §8).
	static func describe(in environment: AppEnvironment, now: Date = Date()) async -> String {
		guard isSignedIn(environment) else { return signedOut }
		await environment.chaseStore.refresh()
		if environment.chaseStore.hasNoChase { return "You have no habits yet. Open Feed the Goose to add one." }
		guard let snapshot = environment.chaseStore.snapshot else { return "Couldn't reach Feed the Goose." }
		let text = standing(snapshot.chase, lead: snapshot.clock.lead(at: now))
		guard snapshot.isOutOfDate else { return text }
		return "\(text) That was \(WidgetContent.age(of: snapshot, at: now)) ago; Feed the Goose couldn't be reached since."
	}

	/// The state and the lead, as a sentence.
	static func standing(_ chase: Chase, lead: Double) -> String {
		switch chase.state {
		case .complete: "The goose is fed. It has the whole loaf."
		case .caught: "The goose got you today."
		case .short: "The day ended with the goose \(WidgetContent.steps(lead)) behind you."
		case .running: "The goose is \(WidgetContent.steps(lead)) behind you."
		}
	}

	/// A missing token is signed out. A token that cannot be read, such as before the first
	/// unlock, is not: the log is queued and counts later.
	static func isSignedIn(_ environment: AppEnvironment) -> Bool {
		do { return try environment.session.token() != nil } catch { return true }
	}

	private static func habitName(_ id: UUID, in environment: AppEnvironment) -> String {
		HabitEntity.all(in: environment).first { $0.id == id }?.name ?? "That log"
	}
}
