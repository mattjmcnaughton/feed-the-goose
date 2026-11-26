import Foundation
import GooseCore
import Observation

/// The Today screen's model (TDD §6.5). It shows the chase `ChaseStore` holds, logs through
/// `LogQueue`, and picks the clip each change deserves. It never decides a day's state or what a
/// log is worth: the lead it shows is the server's, counted down with `ChaseClock`.
@MainActor @Observable
final class TodayModel {
	enum State: Equatable {
		/// No chase yet, and no answer from the server.
		case loading
		/// The server says there is no habit for the current day.
		case noChase
		/// No chase was ever received, and the last fetch failed.
		case unavailable(APIError)
		case showing(ChaseSnapshot)
	}

	/// What the last thing the user did came to, shown under the headline.
	enum Line: Equatable {
		/// The server counted a log; `steps` is what its event says it earned.
		case logged(amount: Int, unit: String, steps: Double, kind: ChaseEventKind)
		case undone(amount: Int, unit: String, steps: Double)
		/// Kept on the phone: it counts when the server can be reached.
		case queued(amount: Int, unit: String)
		/// Its day settled before it arrived, so it was dropped.
		case tooLate(amount: Int, unit: String)
		/// The server refused it, so it was dropped.
		case rejected(amount: Int, unit: String)
		/// It could neither be kept nor sent.
		case notSaved(amount: Int, unit: String)
		/// Logs that were waiting went through.
		case sent(count: Int)
		case undoFailed(tooLate: Bool)
	}

	/// A clip on screen: what plays, from when, and the lead it starts from.
	struct Playing: Equatable {
		var clip: Clip
		var start: Date
		/// The lead shown just before the change, in steps.
		var fromLead: Double
		/// The stage just before the change: the goose that snaps, feasts or catches is the one
		/// that was chasing. A catch resets the stage, so the still scene after it is smaller.
		var stage: Int
		var date: LocalDate
	}

	var line: Line?
	/// The log that Undo takes back: the last one this screen logged and the server counted.
	var undoable: UUID?
	private(set) var pending: [LogRequest] = []
	private(set) var playing: Playing?

	let environment: AppEnvironment
	let now: @Sendable () -> Date
	let timeZone: TimeZone

	init(environment: AppEnvironment, now: @escaping @Sendable () -> Date = Date.init, timeZone: TimeZone = .current) {
		self.environment = environment
		self.now = now
		self.timeZone = timeZone
		pending = environment.logQueue.pending()
	}

	var state: State {
		let store = environment.chaseStore
		if let snapshot = store.snapshot { return .showing(snapshot) }
		if store.hasNoChase { return .noChase }
		if let error = store.lastError { return .unavailable(error) }
		return .loading
	}

	var snapshot: ChaseSnapshot? { environment.chaseStore.snapshot }

	/// The lead to show at `date`: the server's, counted down while the day runs.
	func lead(at date: Date) -> Double? { snapshot?.clock.lead(at: date) }

	// MARK: - Refreshing

	/// Fetches the chase when Today appears, then every 60 seconds and at the times the server
	/// named, until the view goes away.
	func run() async {
		while !Task.isCancelled {
			await refresh()
			let wait = nextRefresh(after: now()).timeIntervalSince(now())
			try? await Task.sleep(for: .seconds(max(1, wait)))
		}
	}

	/// The next time to fetch: in 60 seconds, or sooner at `caught_at`, `day_ends_at` or
	/// `next_day_starts_at`, so the app learns of a catch or the day's end when it happens. Each
	/// is a second late, so the server has passed the instant too.
	func nextRefresh(after date: Date) -> Date {
		var next = date.addingTimeInterval(60)
		guard let snapshot else { return next }
		let chase = snapshot.chase
		for instant in [chase.caughtAt, chase.dayEndsAt, chase.nextDayStartsAt].compactMap({ $0 }) {
			let due = snapshot.clock.deviceTime(of: instant).addingTimeInterval(1)
			if due > date, due < next { next = due }
		}
		return next
	}

	/// Fetches the chase, plays Feast or Peck if the day finished elsewhere, and sends any logs
	/// that are waiting.
	func refresh() async {
		let before = lead(at: now())
		let stage = snapshot?.chase.streak.stage
		if let clip = await environment.chaseStore.refresh() {
			play(clip, from: before, stage: stage)
		}
		await sendWaiting()
	}

	/// Sends the logs waiting in the queue, such as after the app comes back online.
	func sendWaiting() async {
		guard !environment.logQueue.pending().isEmpty else {
			pending = []
			return
		}
		let outcomes = await environment.logQueue.drain()
		pending = environment.logQueue.pending()
		let sent = outcomes.filter { if case .logged = $0 { true } else { false } }.count
		if let late = outcomes.first(where: { if case .tooLate = $0 { true } else { false } }) {
			line = .tooLate(amount: late.request.amount ?? 0, unit: unit(of: late.request.habitID))
		} else if sent > 0 {
			line = .sent(count: sent)
		}
	}

	// MARK: - Logging

	func log(_ habit: ChaseHabit, amount: Int) async {
		let before = lead(at: now())
		let stage = snapshot?.chase.streak.stage
		let outcome = await environment.logQueue.log(habitID: habit.habitID, amount: amount, source: .app)
		pending = environment.logQueue.pending()
		switch outcome {
		case let .logged(_, result, clip):
			line = .logged(amount: result.log.amount, unit: habit.unit, steps: result.event.steps, kind: result.event.kind)
			undoable = result.log.id
			if let clip { play(clip, from: before, stage: stage) }
		case .queued:
			line = .queued(amount: amount, unit: habit.unit)
			undoable = nil
		case .tooLate:
			line = .tooLate(amount: amount, unit: habit.unit)
			undoable = nil
		case .rejected:
			line = .rejected(amount: amount, unit: habit.unit)
		case .notSaved:
			line = .notSaved(amount: amount, unit: habit.unit)
		}
	}

	/// Takes back the last log this screen made.
	func undo() async {
		guard let id = undoable else { return }
		do {
			let result = try await environment.logs.undoLog(id: id)
			environment.chaseStore.receive(result)
			undoable = nil
			playing = nil
			line = .undone(amount: result.log.amount, unit: unit(of: result.log.habitID), steps: result.event.steps)
		} catch APIError.daySettled {
			undoable = nil
			line = .undoFailed(tooLate: true)
		} catch {
			line = .undoFailed(tooLate: false)
		}
	}

	// MARK: - Clips

	private func play(_ clip: Clip, from lead: Double?, stage: Int?) {
		guard let snapshot else { return }
		let date = snapshot.chase.date
		playing = Playing(
			clip: clip, start: now(), fromLead: lead ?? snapshot.chase.lead,
			stage: stage ?? snapshot.chase.streak.stage, date: date
		)
		// Feast and Peck play once per day per device.
		if clip != .snap { environment.chaseStore.markPlayed(clip, on: date) }
	}

	/// Called when a clip has played through: the still scene for the day takes over. Feast and
	/// Peck end on the complete and caught scenes, drawn at the server's new stage.
	func clipFinished(_ finished: Playing) {
		if playing == finished { playing = nil }
	}

	private func unit(of habitID: UUID) -> String {
		snapshot?.chase.habits.first { $0.habitID == habitID }?.unit ?? ""
	}

	/// The habit a queued log is for, for the list of waiting logs.
	func habit(_ id: UUID) -> ChaseHabit? {
		snapshot?.chase.habits.first { $0.habitID == id }
	}
}
