import Foundation
import GooseCore
import Testing
@testable import FeedTheGoose

/// A habit server that keeps a list, records each request, and refuses when told to.
actor FakeHabitServer: HabitService {
	var list: [Habit]
	var refusal: APIError?
	private(set) var updates: [(UUID, HabitChanges)] = []
	private(set) var created: [HabitDraft] = []

	init(_ list: [Habit], refusal: APIError? = nil) {
		self.list = list
		self.refusal = refusal
	}

	func refuse(with error: APIError?) { refusal = error }

	func habits() async throws -> [Habit] {
		if let refusal { throw refusal }
		return list
	}

	func createHabit(_ draft: HabitDraft) async throws -> Habit {
		if let refusal { throw refusal }
		created.append(draft)
		let habit = HabitSamples.habit(draft.name, position: list.count, effectiveFrom: "2026-11-27")
		list.append(habit)
		return habit
	}

	func updateHabit(id: UUID, _ changes: HabitChanges) async throws -> Habit {
		if let refusal { throw refusal }
		updates.append((id, changes))
		return list.first { $0.id == id }!
	}

	func archiveHabit(id: UUID) async throws -> Habit {
		if let refusal { throw refusal }
		return list.first { $0.id == id }!
	}
}

enum HabitSamples {
	/// The fixture chase's day.
	static let today: LocalDate = "2026-11-26"

	static func habit(_ name: String, position: Int, target: Int = 10, effectiveFrom: LocalDate = "2026-10-22", archivedFrom: LocalDate? = nil) -> Habit {
		Habit(id: UUID(), name: name, unit: "reps", target: target, chunk: 5, position: position, effectiveFrom: effectiveFrom, archivedFrom: archivedFrom)
	}

	static func habits(_ count: Int) -> [Habit] {
		(0 ..< count).map { habit("Habit \($0 + 1)", position: $0) }
	}

	/// An environment on the fixtures, with `server` for the habits and the fixture chase cached.
	static func environment(_ server: any HabitService) -> AppEnvironment {
		let fixtures = FixtureServices()
		let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "habits-\(UUID().uuidString)"))
		shared.setChaseSnapshot(ChaseSnapshot(chase: try! Fixtures.load("example-day-07-chase").response(), receivedAt: Date()))
		return AppEnvironment(
			auth: fixtures, account: fixtures, habits: server, logs: fixtures, chase: fixtures,
			session: .inMemory(token: "t"), shared: shared
		)
	}
}

@MainActor
struct HabitsModelTests {
	@Test func addingIsDisabledAtEightActiveHabitsButNotWhenOneIsArchived() async {
		let eight = HabitSamples.habits(8)
		let full = HabitsModel(environment: HabitSamples.environment(FakeHabitServer(eight)))
		await full.load()
		#expect(full.activeCount == 8)
		#expect(!full.canAdd)

		var oneArchived = eight
		oneArchived[3].archivedFrom = "2026-11-27"
		let room = HabitsModel(environment: HabitSamples.environment(FakeHabitServer(oneArchived)))
		await room.load()
		#expect(room.activeCount == 7)
		#expect(room.canAdd)
	}

	@Test func aFailedReadIsShownAsAFailureNotAnEmptyList() async {
		let model = HabitsModel(environment: HabitSamples.environment(FakeHabitServer([], refusal: .transport("offline"))))
		await model.load()
		#expect(model.state == .failed("Couldn't reach the server. Check your connection and try again."))
		#expect(!model.canAdd)
	}

	@Test func aRefusedArchiveIsShownAndTheListIsTheServers() async {
		let habits = HabitSamples.habits(3)
		let server = FakeHabitServer(habits)
		let model = HabitsModel(environment: HabitSamples.environment(server))
		await model.load()
		await server.refuse(with: .notFound)
		await model.archive(habits[1])
		#expect(model.problem == "That habit is no longer there.")
		#expect(model.habits.map(\.id) == habits.map(\.id))
	}

	@Test func draggingAHabitDownSendsTheIndexItLandsOn() async {
		let habits = HabitSamples.habits(4)
		let server = FakeHabitServer(habits)
		let model = HabitsModel(environment: HabitSamples.environment(server))
		await model.load()
		// A list's drag of the first row below the third reports destination 3: it lands at 2.
		await model.move(from: [0], to: 3)
		// Dropping a row where it was sends nothing.
		await model.move(from: [2], to: 3)
		let updates = await server.updates
		#expect(updates.map(\.0) == [habits[0].id])
		#expect(updates.map(\.1) == [HabitChanges(position: 2)])
	}

	@Test func noticesComeFromTheServersDatesAndTodaysChase() async throws {
		let chase: Chase = try Fixtures.load("example-day-07-chase").response()
		let pushups = try #require(chase.habits.first)
		let changedTarget = Habit(
			id: pushups.habitID, name: pushups.name, unit: pushups.unit, target: pushups.target + 10, chunk: pushups.chunk,
			position: 0, effectiveFrom: "2026-10-22", archivedFrom: nil
		)
		let tomorrow = HabitSamples.habit("Stretching", position: 1, effectiveFrom: "2026-11-27")
		let archived = HabitSamples.habit("Reading", position: 2, archivedFrom: "2026-11-27")
		let steady = HabitSamples.habit("Steady", position: 3)
		let model = HabitsModel(environment: HabitSamples.environment(FakeHabitServer([changedTarget, tomorrow, archived, steady])))
		await model.load()
		#expect(model.today == HabitSamples.today)
		#expect(model.notice(for: changedTarget) == "50 reps today, 60 from tomorrow")
		#expect(model.notice(for: tomorrow) == "Starts tomorrow")
		#expect(model.notice(for: archived) == "Archived from tomorrow. It still counts today.")
		#expect(model.notice(for: steady) == nil)
	}
}

@MainActor
struct HabitFormModelTests {
	@Test func emptyAndNonPositiveFieldsAreRefusedBeforeAnythingIsSent() async {
		var sent: [HabitFormModel.Output] = []
		let model = HabitFormModel { sent.append($0) }
		model.name = "  "
		model.unit = ""
		model.target = "0"
		model.chunk = "2.5"
		#expect(await !model.submit())
		#expect(sent.isEmpty)
		#expect(Set(model.errors.keys) == [.name, .unit, .target, .chunk])
	}

	@Test func aNewHabitIsSentTrimmed() async {
		var sent: [HabitFormModel.Output] = []
		let model = HabitFormModel { sent.append($0) }
		model.name = " Pushups "
		model.unit = "reps\n"
		model.target = "50"
		model.chunk = " 10"
		#expect(await model.submit())
		#expect(sent == [.create(HabitDraft(name: "Pushups", unit: "reps", target: 50, chunk: 10))])
	}

	@Test func anEditSendsOnlyWhatChangedAndSaysANewTargetCountsTomorrow() async {
		let habit = HabitSamples.habit("Pushups", position: 0, target: 50)
		var sent: [HabitFormModel.Output] = []
		let model = HabitFormModel(editing: habit) { sent.append($0) }
		#expect(!model.changesTarget)
		model.target = "60"
		#expect(model.changesTarget)
		#expect(await model.submit())
		#expect(sent == [.update(habit, HabitChanges(target: 60))])

		let untouched = HabitFormModel(editing: habit) { sent.append($0) }
		#expect(await untouched.submit())
		#expect(sent.count == 1)
	}

	@Test func theServersRefusalLandsOnTheFieldItNames() async {
		let model = HabitFormModel { _ in
			throw APIError.invalid([FieldError(field: "name", message: "String should have at least 1 character")])
		}
		model.name = "Pushups"
		model.unit = "reps"
		model.target = "50"
		model.chunk = "10"
		#expect(await !model.submit())
		#expect(model.errors == [.name: "String should have at least 1 character"])
		#expect(model.state == .editing)
	}

	@Test func aRefusalWithoutAFieldIsShownForTheForm() async {
		let model = HabitFormModel { _ in throw APIError.invalid([]) }
		model.name = "Ninth"
		model.unit = "reps"
		model.target = "5"
		model.chunk = "1"
		#expect(await !model.submit())
		#expect(model.problem == "The server refused this change. A day can have at most 8 habits.")
	}

	@Test func addingThroughTheListModelReadsTheListAgain() async {
		let server = FakeHabitServer([])
		let list = HabitsModel(environment: HabitSamples.environment(server))
		await list.load()
		let form = HabitFormModel { output in
			if case let .create(draft) = output { try await list.add(draft) }
		}
		form.name = "Pushups"
		form.unit = "reps"
		form.target = "50"
		form.chunk = "10"
		#expect(await form.submit())
		#expect(list.habits.map(\.name) == ["Pushups"])
		#expect(list.notice(for: list.habits[0]) == "Starts tomorrow")
	}
}
