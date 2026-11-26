import Foundation
import GooseCore
import Testing

/// The fake environment must let a screen, a widget or an intent be driven through a log
/// without a server: a log moves the chase it caches, and an undo moves it back.
@MainActor
struct FixtureServicesTests {
	let pushups = UUID(uuidString: "22222222-2222-4222-8222-000000000001")!
	let reading = UUID(uuidString: "22222222-2222-4222-8222-000000000003")!

	func request(_ habit: UUID, amount: Int? = nil) -> LogRequest {
		LogRequest(id: .v7(at: Date()), habitID: habit, amount: amount, loggedAt: Date(), source: .widget)
	}

	@Test func aLogThroughTheQueueMovesTheCachedChase() async throws {
		let environment = AppEnvironment.fake
		// The fixture chase: lead 80, pushups 20 of 50, three habits.
		let before = try #require(environment.shared.chaseSnapshot).chase
		#expect(before.lead == 80)

		let outcome = await environment.logQueue.log(habitID: pushups, amount: nil, source: .widget)
		guard case let .logged(_, result, clip) = outcome else { Issue.record("not logged: \(outcome)"); return }
		#expect(clip == .snap)
		#expect(result.log.amount == 10)
		#expect(result.log.source == .widget)

		// 10 of a 50-rep habit worth a third of 100 steps is 6.7 steps (the API spec's example).
		let after = try #require(environment.shared.chaseSnapshot).chase
		#expect(after.habits[0].logged == 30)
		#expect(after.lead == 86.7)
		#expect(after.asOf > before.asOf)
		#expect(try await environment.chase.today() == after)

		// Another process, such as the widget extension, builds its own fake over the same App
		// Group and must not fetch the older fixture chase back.
		let widget = AppEnvironment.fake(shared: environment.shared)
		await widget.chaseStore.refresh()
		#expect(widget.shared.chaseSnapshot?.chase.habits[0].logged == 30)
	}

	@Test func finishingTheLastHabitCompletesTheDayAndUndoReopensIt() async throws {
		let services = FixtureServices()
		_ = try await services.createLog(request(pushups, amount: 30))
		let last = try await services.createLog(request(reading, amount: 20))
		#expect(last.event.kind == .complete)
		#expect(last.chase.state == .complete)
		#expect(last.chase.streak.completeDays == 14)
		#expect(try await services.logs(on: last.chase.date).first?.id == last.log.id)

		let undone = try await services.undoLog(id: last.log.id)
		#expect(undone.event.kind == .undone)
		#expect(undone.chase.state == .running)
		#expect(undone.chase.habits[2].logged == 0)
		#expect(undone.chase.streak.completeDays == 13)
		#expect(try await services.logs(on: last.chase.date).first?.undoneAt != nil)
	}

	@Test func anUnknownHabitIsNotFound() async {
		await #expect(throws: APIError.notFound) {
			try await FixtureServices().createLog(request(UUID()))
		}
	}
}
