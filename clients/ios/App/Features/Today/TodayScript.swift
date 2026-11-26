#if DEBUG
	import Foundation
	import GooseCore

	/// A scripted server for recording Today with `-FTGUseFixtures` (T16's proof). The fixture
	/// fake answers every log with the same recorded chase, so it cannot show a lead rising, a
	/// day finishing or a catch. `-FTGTodayScript day` starts a day like the fixtures' example
	/// at about 80 steps; `-FTGTodayScript caught-soon` starts one about to be caught.
	///
	/// This stands in for the server in a debug build only, the way a test fake does: it follows
	/// TDD §5.3 so the screen can be driven, and the app itself still computes nothing.
	enum TodayScript {
		static func environment(
			replacing base: AppEnvironment,
			arguments: [String] = ProcessInfo.processInfo.arguments
		) -> AppEnvironment? {
			guard base.usesFixtures, let i = arguments.firstIndex(of: "-FTGTodayScript") else { return nil }
			let name = arguments.indices.contains(i + 1) ? arguments[i + 1] : "day"
			// A store of its own, emptied on each launch, so the fixtures' cached chase and the
			// clips played on an earlier run do not carry over.
			let shared = SharedStore(directory: base.shared.directory.appending(path: "today-script", directoryHint: .isDirectory))
			try? FileManager.default.removeItem(at: shared.directory)
			let server = ScriptedServer(caughtSoon: name == "caught-soon", now: Date())
			return AppEnvironment(
				auth: base.auth, account: base.account, habits: base.habits, logs: server, chase: server,
				session: base.session, shared: shared, usesFixtures: true
			)
		}
	}

	actor ScriptedServer: LogService, ChaseService {
		struct Item {
			let id: UUID
			let name: String, unit: String, target: Int, chunk: Int
		}

		struct Entry {
			var log: LogEntry
			var undone = false
		}

		let items = [
			Item(id: UUID(uuidString: "22222222-2222-4222-8222-000000000001")!, name: "Pushups", unit: "reps", target: 50, chunk: 10),
			Item(id: UUID(uuidString: "22222222-2222-4222-8222-000000000002")!, name: "Workout", unit: "minutes", target: 30, chunk: 10),
			Item(id: UUID(uuidString: "22222222-2222-4222-8222-000000000003")!, name: "Reading", unit: "pages", target: 20, chunk: 5),
		]
		let startsAt: Date
		let endsAt: Date
		let startingLead: Double
		let pace: Double
		var entries: [Entry] = []

		init(caughtSoon: Bool, now: Date) {
			if caughtSoon {
				// Caught about 12 seconds after launch: a fast pace keeps the wait short.
				pace = 300
				startsAt = now.addingTimeInterval(-60)
				endsAt = startsAt.addingTimeInterval(18 * 3600)
				// Walked 5 of 6 at launch: 1 step left.
				startingLead = 6
			} else {
				pace = 100.0 / 18
				startsAt = now.addingTimeInterval(-12 * 3600)
				endsAt = startsAt.addingTimeInterval(18 * 3600)
				startingLead = 100
			}
			let at = startsAt.addingTimeInterval(3 * 3600)
			let seeded: [(Int, Int)] = caughtSoon ? [] : [(0, 20), (1, 30)]
			for (index, amount) in seeded {
				let log = LogEntry(id: UUID(), habitID: items[index].id, amount: amount, loggedAt: at, source: .app, date: "2026-11-26", steps: 0, undoneAt: nil)
				entries.append(Entry(log: log))
			}
		}

		func createLog(_ request: LogRequest) async throws -> LogResult {
			guard let item = items.first(where: { $0.id == request.habitID }) else { throw APIError.notFound }
			let before = chase(at: Date())
			let log = LogEntry(
				id: request.id, habitID: request.habitID, amount: request.amount ?? item.chunk, loggedAt: request.loggedAt,
				source: request.source, date: before.date, steps: 0, undoneAt: nil
			)
			entries.append(Entry(log: log))
			let after = chase(at: Date())
			let earned = after.earned - before.earned
			let kind: ChaseEventKind = before.state == .caught ? .caught : after.state == .complete ? .complete : .gain
			var stored = log
			stored.steps = earned
			return LogResult(log: stored, event: ChaseEvent(kind: kind, habitID: item.id, steps: earned), chase: after)
		}

		func undoLog(id: UUID) async throws -> LogResult {
			guard let index = entries.firstIndex(where: { $0.log.id == id }) else { throw APIError.notFound }
			let before = chase(at: Date())
			entries[index].undone = true
			let after = chase(at: Date())
			let steps = before.earned - after.earned
			var log = entries[index].log
			log.steps = steps
			log.undoneAt = Date()
			return LogResult(log: log, event: ChaseEvent(kind: .undone, habitID: log.habitID, steps: steps), chase: after)
		}

		func logs(on date: LocalDate) async throws -> [LogEntry] { entries.map(\.log) }
		func today() async throws -> Chase { chase(at: Date()) }
		func days(from: LocalDate, to: LocalDate) async throws -> [DaySummary] { [] }

		/// The day at `at`, by TDD §5.3's rules: equal shares, logs capped at their habit's
		/// share, the lead frozen when the day completes, caught when it reaches 0.
		private func chase(at now: Date) -> Chase {
			let share = 100.0 / Double(items.count)
			var logged = Dictionary(uniqueKeysWithValues: items.map { ($0.id, 0) })
			var earned = 0.0
			var completedAt: Date?
			var caughtAt: Date?
			let walked = { (t: Date) in self.pace * max(0, min(t, self.endsAt).timeIntervalSince(self.startsAt)) / 3600 }
			let live = entries.filter { !$0.undone }.map(\.log).sorted { $0.loggedAt < $1.loggedAt }
			func catchTime(after t: Date) -> Date? {
				let lead = startingLead + earned - walked(t)
				let at = t.addingTimeInterval(max(0, lead) / pace * 3600)
				return at <= endsAt ? at : nil
			}
			for log in live where completedAt == nil {
				if let c = catchTime(after: startsAt), c <= log.loggedAt, caughtAt == nil { caughtAt = c }
				if caughtAt != nil { break }
				let item = items.first { $0.id == log.habitID }!
				let before = logged[item.id]!
				logged[item.id] = before + log.amount
				let gained = share * Double(min(before + log.amount, item.target) - min(before, item.target)) / Double(item.target)
				earned += gained
				if items.allSatisfy({ logged[$0.id]! >= $0.target }) { completedAt = log.loggedAt }
			}
			if completedAt == nil, caughtAt == nil, let c = catchTime(after: startsAt), c <= now { caughtAt = c }
			let state: ChaseState
			let lead: Double
			if let completedAt {
				state = .complete
				lead = startingLead + earned - walked(completedAt)
			} else if caughtAt != nil {
				state = .caught
				lead = 0
			} else {
				lead = startingLead + earned - walked(now)
				state = now >= endsAt ? .short : .running
			}
			let habits = items.map { item in
				let amount = logged[item.id]!
				return ChaseHabit(
					habitID: item.id, name: item.name, unit: item.unit, target: item.target, chunk: item.chunk,
					logged: amount, steps: share * Double(min(amount, item.target)) / Double(item.target), done: amount >= item.target
				)
			}
			let complete = state == .complete
			return Chase(
				date: "2026-11-26", pursuer: .goose, state: state, asOf: now, lead: lead, startingLead: startingLead,
				earned: earned, walked: walked(completedAt ?? caughtAt ?? now), stepsPerHour: pace, dayStartsAt: startsAt,
				dayEndsAt: endsAt, nextDayStartsAt: endsAt.addingTimeInterval(6 * 3600),
				caughtAt: state == .running ? catchTime(after: now) : caughtAt, habits: habits,
				streak: state == .caught ? Streak(completeDays: 0, stage: 0) : Streak(completeDays: complete ? 14 : 13, stage: complete ? 3 : 2)
			)
		}
	}
#endif
