import Foundation
import GooseCore
import Testing
@testable import FeedTheGoose

/// A server for the session's two questions, sign-in and the habit list, that records what it
/// was asked. The other services answer from the fixtures.
actor FakeSessionServer: AuthService, HabitService {
	var sessionResult: Result<NewSession, APIError>
	var habitsResult: Result<[Habit], APIError>
	private(set) var created: [(identityToken: String, timeZone: String, deviceName: String)] = []
	private(set) var deleted: [SessionReference] = []
	/// The stored token at the moment `deleteSession` was called.
	private(set) var tokenWhenDeleting: String?
	private let session: SessionStore

	init(session: SessionStore, sessionResult: Result<NewSession, APIError>, habitsResult: Result<[Habit], APIError>) {
		self.session = session
		self.sessionResult = sessionResult
		self.habitsResult = habitsResult
	}

	func setHabits(_ result: Result<[Habit], APIError>) { habitsResult = result }

	func createSession(identityToken: String, timeZone: String, deviceName: String) async throws -> NewSession {
		created.append((identityToken, timeZone, deviceName))
		return try sessionResult.get()
	}

	func sessions() async throws -> [AppSession] { [] }

	func deleteSession(_ reference: SessionReference) async throws {
		deleted.append(reference)
		tokenWhenDeleting = try? session.token()
	}

	func habits() async throws -> [Habit] { try habitsResult.get() }
	func createHabit(_ draft: HabitDraft) async throws -> Habit { throw APIError.notImplemented }
	func updateHabit(id: UUID, _ changes: HabitChanges) async throws -> Habit { throw APIError.notImplemented }
	func archiveHabit(id: UUID) async throws -> Habit { throw APIError.notImplemented }
}

struct StubIdentity: IdentityProvider {
	var result: Result<String, APIError> = .success("identity-for-test")
	func identityToken(loginHint: String) async throws -> String { try result.get() }
}

@MainActor
struct SessionModelTests {
	let session = SessionStore.inMemory()
	let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "session-model-\(UUID().uuidString)"))
	let newSession: NewSession
	let someHabits: [Habit]
	let server: FakeSessionServer

	init() throws {
		newSession = try Fixtures.load("auth-session-create").response()
		someHabits = try Fixtures.load("habits-list").response()
		server = FakeSessionServer(session: session, sessionResult: .success(newSession), habitsResult: .success([]))
	}

	func model(
		identity: (any IdentityProvider)? = StubIdentity(),
		refusals: AsyncStream<Void> = AsyncStream { $0.finish() }
	) -> SessionModel {
		let fixtures = FixtureServices()
		let environment = AppEnvironment(
			auth: server, account: fixtures, habits: server, logs: fixtures, chase: fixtures,
			session: session, shared: shared
		)
		return SessionModel(
			environment: environment, identity: identity, refusals: refusals,
			deviceName: "Test iPhone", timeZone: { TimeZone(identifier: "Europe/Lisbon")! }
		)
	}

	@Test func noTokenStartsSignedOut() async {
		let model = model()
		await model.start()
		#expect(model.state == .signedOut)
	}

	@Test func aStoredTokenWithoutHabitsAsksForHabits() async throws {
		try session.save("stored")
		let model = model()
		await model.start()
		#expect(model.state == .needsHabits)
	}

	@Test func aStoredTokenWithHabitsShowsTheChase() async throws {
		try session.save("stored")
		await server.setHabits(.success(someHabits))
		let model = model()
		await model.start()
		#expect(model.state == .signedIn)
		#expect(shared.habits == someHabits)
	}

	@Test func signInSwapsTheIdentityTokenAndSavesTheSession() async throws {
		let model = model()
		await model.start()
		try await model.signIn(email: "matt@example.com")

		let created = await server.created
		#expect(created.count == 1)
		#expect(created.first?.identityToken == "identity-for-test")
		#expect(created.first?.timeZone == "Europe/Lisbon")
		#expect(created.first?.deviceName == "Test iPhone")
		#expect(try session.token() == newSession.sessionToken)
		#expect(model.state == .needsHabits)
	}

	@Test func anEmailOffTheAllowlistSavesNothing() async throws {
		await server.setSessionResult(.failure(.identityNotAdmitted))
		let model = model()
		await model.start()
		await #expect(throws: APIError.identityNotAdmitted) { try await model.signIn(email: "stranger@example.com") }
		#expect(try session.token() == nil)
		#expect(model.state == .signedOut)
	}

	@Test func aFailedHabitCheckIsNotAnEmptyList() async throws {
		try session.save("stored")
		await server.setHabits(.failure(.transport("offline")))
		let model = model()
		await model.start()
		#expect(model.state == .unreachable)
	}

	@Test func aFailedHabitCheckFallsBackToTheCachedHabits() async throws {
		try session.save("stored")
		shared.setHabits(someHabits)
		await server.setHabits(.failure(.transport("offline")))
		let model = model()
		await model.start()
		#expect(model.state == .signedIn)
	}

	@Test func aRefusedSessionAnywhereReturnsToSignIn() async throws {
		try session.save("stored")
		shared.setChaseSnapshot(ChaseSnapshot(chase: try Fixtures.load("example-day-07-chase").response(), receivedAt: .now))
		await server.setHabits(.success(someHabits))
		let (refusals, refuse) = AsyncStream.makeStream(of: Void.self)
		let model = model(refusals: refusals)
		let running = Task { await model.run() }
		while model.state == .starting { await Task.yield() }
		#expect(model.state == .signedIn)

		refuse.yield()
		refuse.finish()
		await running.value

		#expect(model.state == .signedOut)
		#expect(model.notice != nil)
		#expect(try session.token() == nil)
		#expect(shared.chaseSnapshot == nil)
		#expect(shared.habits == nil)
		#expect(model.environment.chaseStore.snapshot == nil)
	}

	@Test func aRefusedHabitCheckReturnsToSignIn() async throws {
		try session.save("revoked")
		await server.setHabits(.failure(.unauthenticated))
		let model = model()
		await model.start()
		#expect(model.state == .signedOut)
		#expect(try session.token() == nil)
	}

	@Test func signOutRevokesTheSessionBeforeForgettingIt() async throws {
		try session.save("stored")
		await server.setHabits(.success(someHabits))
		let model = model()
		await model.start()
		await model.signOut()

		#expect(await server.deleted == [.current])
		#expect(await server.tokenWhenDeleting == "stored")
		#expect(try session.token() == nil)
		#expect(shared.habits == nil)
		#expect(model.state == .signedOut)
		#expect(model.notice == nil)
	}

	@Test func signOutWorksWhenTheServerCannotBeReached() async throws {
		try session.save("stored")
		let fixtures = FixtureServices()
		let environment = AppEnvironment(
			auth: UnreachableAuth(), account: fixtures, habits: server, logs: fixtures, chase: fixtures,
			session: session, shared: shared
		)
		let model = SessionModel(environment: environment, identity: StubIdentity())
		await model.signOut()
		#expect(try session.token() == nil)
		#expect(model.state == .signedOut)
	}

	@Test func aBuildWithoutAnIdentityProviderCannotSignIn() async {
		let model = model(identity: nil)
		#expect(!model.canSignIn)
		await #expect(throws: APIError.notImplemented) { try await model.signIn(email: "matt@example.com") }
		#expect(await server.created.isEmpty)
	}
}

extension FakeSessionServer {
	func setSessionResult(_ result: Result<NewSession, APIError>) { sessionResult = result }
}

private struct UnreachableAuth: AuthService {
	func createSession(identityToken: String, timeZone: String, deviceName: String) async throws -> NewSession {
		throw APIError.transport("offline")
	}

	func sessions() async throws -> [AppSession] { throw APIError.transport("offline") }
	func deleteSession(_ session: SessionReference) async throws { throw APIError.transport("offline") }
}
