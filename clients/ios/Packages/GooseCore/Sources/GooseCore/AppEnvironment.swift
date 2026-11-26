import Foundation

/// The services and stores the app, the widgets and the intents run on (TDD §6.4). The
/// composition root builds the live one; `fake` answers from the fixtures. Each feature's entry
/// view takes one in its initializer.
public struct AppEnvironment: Sendable {
	public let auth: any AuthService
	public let account: any AccountService
	public let habits: any HabitService
	public let logs: any LogService
	public let chase: any ChaseService
	public let session: SessionStore
	public let shared: SharedStore
	public let chaseStore: ChaseStore
	public let logQueue: LogQueue
	/// True for the fake environment.
	public let usesFixtures: Bool

	public init(
		auth: any AuthService,
		account: any AccountService,
		habits: any HabitService,
		logs: any LogService,
		chase: any ChaseService,
		session: SessionStore,
		shared: SharedStore,
		usesFixtures: Bool = false,
		now: @escaping @Sendable () -> Date = Date.init,
		reloadWidgets: @escaping @Sendable () -> Void = {}
	) {
		self.auth = auth
		self.account = account
		self.habits = habits
		self.logs = logs
		self.chase = chase
		self.session = session
		self.shared = shared
		self.usesFixtures = usesFixtures
		chaseStore = ChaseStore(service: chase, shared: shared, now: now, reloadWidgets: reloadWidgets)
		logQueue = LogQueue(directory: shared.queueDirectory, service: logs, chaseStore: chaseStore, now: now)
	}

	/// The fake environment, signed in, with the fixtures' habits and chase already cached in
	/// `shared`, so a widget reading the App Group sees them too.
	public static func fake(shared: SharedStore, reloadWidgets: @escaping @Sendable () -> Void = {}) -> AppEnvironment {
		if shared.chaseSnapshot == nil {
			shared.setChaseSnapshot(ChaseSnapshot(chase: Fixtures.response("example-day-07-chase"), receivedAt: Date()))
		}
		// The app, the widget extension and the intents each build their own fake. Starting from
		// the cached chase keeps a log made in one process when another one fetches.
		let services = FixtureServices(chase: shared.chaseSnapshot?.chase)
		if shared.habits == nil {
			shared.setHabits(Fixtures.response("habits-list"))
		}
		return AppEnvironment(
			auth: services,
			account: services,
			habits: services,
			logs: services,
			chase: services,
			session: .inMemory(token: Fixtures.response("auth-session-create", as: NewSession.self).sessionToken),
			shared: shared,
			usesFixtures: true,
			reloadWidgets: reloadWidgets
		)
	}

	/// The fake environment in a fresh temporary folder, for previews and tests.
	public static var fake: AppEnvironment {
		fake(shared: SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "goose-fake-\(UUID().uuidString)")))
	}
}
