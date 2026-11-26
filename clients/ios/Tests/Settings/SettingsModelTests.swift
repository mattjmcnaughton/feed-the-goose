import Foundation
import GooseCore
import Testing
@testable import FeedTheGoose

/// An account server that keeps what it is sent, records each write, and refuses when told to.
actor FakeAccountServer: AccountService {
	var accountValue: Account = try! Fixtures.load("me-get").response()
	var remindersValue = Reminders(enabled: false, whenLeadBelow: 30, quietHours: nil)
	var profileValue = ProfileSettings(handle: "matt", isPublic: false)
	var keyList: [Key] = try! Fixtures.load("keys-list").response()
	var refusal: APIError?
	private(set) var accountChanges: [AccountChanges] = []
	private(set) var reminderWrites: [Reminders] = []
	private(set) var registrations: [(UUID, DeviceRegistration)] = []
	private(set) var deletedDevices: [UUID] = []

	func refuse(with error: APIError?) { refusal = error }

	func account() async throws -> Account { accountValue }

	func updateAccount(_ changes: AccountChanges) async throws -> Account {
		accountChanges.append(changes)
		if let refusal { throw refusal }
		accountValue.pending = PendingDay(
			effectiveFrom: "2026-11-27", timeZone: changes.timeZone ?? accountValue.timeZone,
			dayStart: changes.dayStart ?? accountValue.dayStart, dayEnd: changes.dayEnd ?? accountValue.dayEnd
		)
		return accountValue
	}

	func deleteAccount() async throws { if let refusal { throw refusal } }

	func keys() async throws -> [Key] { keyList }

	func createKey(kind: KeyKind, name: String) async throws -> NewKey {
		let key = Key(id: UUID(), kind: kind, name: name, createdAt: Date(), lastUsedAt: nil)
		keyList.append(key)
		return NewKey(key: key, secret: "ftg_test-secret-\(key.id.uuidString)")
	}

	func deleteKey(id: UUID) async throws { keyList.removeAll { $0.id == id } }

	func profileSettings() async throws -> ProfileSettings { profileValue }

	func updateProfileSettings(handle: String, isPublic: Bool) async throws -> ProfileSettings {
		if let refusal { throw refusal }
		profileValue = ProfileSettings(handle: handle, isPublic: isPublic)
		return profileValue
	}

	func publicProfile(handle: String) async throws -> PublicProfile { try Fixtures.load("public-profile-get").response() }

	func reminders() async throws -> Reminders { remindersValue }

	func updateReminders(_ reminders: Reminders) async throws -> Reminders {
		reminderWrites.append(reminders)
		remindersValue = reminders
		return reminders
	}

	func registerDevice(installationID: UUID, _ registration: DeviceRegistration) async throws {
		registrations.append((installationID, registration))
	}

	func deleteDevice(installationID: UUID) async throws { deletedDevices.append(installationID) }
}

/// iOS's answers to a permission request and a token request, chosen by the test.
struct FakeNotifications: RemoteNotifications {
	var granted = true
	var token: Result<Data, PushTokenTimeout> = .success(Data([0x0A, 0xFF, 0x00, 0x42]))

	func requestAuthorization() async throws -> Bool { granted }
	func deviceToken() async throws -> Data { try token.get() }
}

enum SettingsSamples {
	static let server = URL(string: "http://localhost:8000")!

	static func environment(_ account: FakeAccountServer) -> AppEnvironment {
		let fixtures = FixtureServices()
		let shared = SharedStore(directory: FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString)"))
		return AppEnvironment(
			auth: fixtures, account: account, habits: fixtures, logs: fixtures, chase: fixtures,
			session: .inMemory(token: "t"), shared: shared
		)
	}

	@MainActor
	static func model(
		_ account: FakeAccountServer = FakeAccountServer(),
		notifications: FakeNotifications = FakeNotifications(),
		zone: String = "America/New_York"
	) -> SettingsModel {
		SettingsModel(
			environment: environment(account), server: server, notifications: notifications,
			deviceZone: { TimeZone(identifier: zone)! }
		)
	}
}

struct DayWindowTests {
	// The server's rule: an end at or before the start is the next morning, and 8 to 22 hours
	// are allowed, both ends included.
	@Test(arguments: [
		("06:00", "00:00", 18.0, true),
		("22:00", "06:00", 8.0, true),
		("06:00", "04:00", 22.0, true),
		("09:00", "16:30", 7.5, false),
		("06:00", "04:30", 22.5, false),
		("06:00", "06:00", 24.0, false),
	])
	func lengthMatchesTheServer(start: String, end: String, hours: Double, allowed: Bool) {
		#expect(DayWindow.hours(start: start, end: end) == hours)
		#expect((DayWindow.problem(start: start, end: end) == nil) == allowed)
	}

	@Test func describesHalfHours() {
		#expect(DayWindow.describe(7.5) == "7 hours 30 minutes")
		#expect(DayWindow.describe(18) == "18 hours")
	}
}

@MainActor
struct SettingsModelTests {
	@Test func aDayChangeSendsOnlyWhatChangedAndShowsAsPending() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server)
		await model.load()

		#expect(await model.saveDay(start: "06:00", end: "01:00", timeZone: "America/New_York"))

		#expect(await server.accountChanges == [AccountChanges(dayEnd: "01:00")])
		#expect(model.account?.dayEnd == "00:00", "today keeps its hours")
		#expect(model.account?.pending?.dayEnd == "01:00")
		#expect(model.upcoming?.dayEnd == "01:00")
	}

	@Test func aDayOutsideEightToTwentyTwoHoursIsRefusedWithoutAsking() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server)
		await model.load()

		#expect(await !model.saveDay(start: "09:00", end: "16:30", timeZone: "America/New_York"))

		#expect(model.dayProblem == "The day must be 8 to 22 hours long. This one is 7 hours 30 minutes.")
		#expect(await server.accountChanges.isEmpty)
	}

	@Test func theServersRefusalIsShownOnTheDay() async {
		let server = FakeAccountServer()
		await server.refuse(with: .invalid([FieldError(field: "day_end", message: "The day must be 8 to 22 hours long")]))
		let model = SettingsSamples.model(server)
		await model.load()

		#expect(await !model.saveDay(start: "06:00", end: "01:00", timeZone: "America/New_York"))
		#expect(model.dayProblem == "The day must be 8 to 22 hours long")
		#expect(model.account?.pending == nil)
	}

	@Test func theZonePromptAppearsOnlyWhenThePhoneDiffers() async {
		let same = SettingsSamples.model(zone: "America/New_York")
		await same.load()
		#expect(same.zonePrompt == nil)

		let moved = SettingsSamples.model(zone: "Europe/Lisbon")
		await moved.load()
		#expect(moved.zonePrompt == "Europe/Lisbon")
	}

	@Test func notNowChangesNothing() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server, zone: "Europe/Lisbon")
		await model.load()

		model.declineZone()

		#expect(model.zonePrompt == nil)
		#expect(await server.accountChanges.isEmpty)
		#expect(model.account?.timeZone == "America/New_York")
		#expect(model.account?.pending == nil)
	}

	@Test func switchingTheZoneSendsOnlyTheZone() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server, zone: "Europe/Lisbon")
		await model.load()

		await model.acceptZone()

		#expect(await server.accountChanges == [AccountChanges(timeZone: "Europe/Lisbon")])
		#expect(model.account?.pending?.timeZone == "Europe/Lisbon")
		#expect(model.zonePrompt == nil, "the upcoming day now uses the phone's zone")
	}

	@Test func turningRemindersOnRegistersThisPhoneFirst() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server)
		await model.load()

		await model.setRemindersEnabled(true)

		let registrations = await server.registrations
		#expect(registrations.count == 1)
		#expect(registrations.first?.0 == model.environment.shared.installationID())
		#expect(registrations.first?.1.apnsToken == "0aff0042")
		#expect(registrations.first?.1.environment == .sandbox)
		#expect(model.reminders?.enabled == true)
		#expect(model.pushNotice == nil)
	}

	@Test func refusedNotificationsLeaveRemindersOff() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server, notifications: FakeNotifications(granted: false))
		await model.load()

		await model.setRemindersEnabled(true)

		#expect(model.reminders?.enabled == false)
		#expect(await server.reminderWrites.isEmpty)
		#expect(await server.registrations.isEmpty)
		#expect(model.pushOutcome == .denied)
	}

	@Test func withNoPushTokenRemindersAreOnAndTheUserIsTold() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server, notifications: FakeNotifications(token: .failure(PushTokenTimeout())))
		await model.load()

		await model.setRemindersEnabled(true)

		#expect(model.reminders?.enabled == true)
		#expect(await server.registrations.isEmpty)
		#expect(model.pushNotice?.contains("no push token") == true)
	}

	@Test func signingOutRemovesThisPhonesRegistration() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server)

		await model.prepareSignOut()

		#expect(await server.deletedDevices == [model.environment.shared.installationID()])
	}

	@Test func aTakenHandleIsRefusedAndTheProfileStaysAsItWas() async {
		let server = FakeAccountServer()
		await server.refuse(with: .handleTaken)
		let model = SettingsSamples.model(server)
		await model.load()
		model.handleDraft = "goose"

		await model.saveProfile(isPublic: true)

		#expect(model.profileProblem == "Someone else has goose. Try another handle.")
		#expect(model.profile == ProfileSettings(handle: "matt", isPublic: false))
		#expect(model.profileURL == nil)
	}

	@Test func aBadHandleIsRefusedWithoutAsking() async {
		let server = FakeAccountServer()
		let model = SettingsSamples.model(server)
		await model.load()
		model.handleDraft = "go"

		await model.saveProfile(isPublic: true)

		#expect(model.profileProblem != nil)
		#expect(await server.profileValue == ProfileSettings(handle: "matt", isPublic: false))
	}

	@Test func turningTheProfileOnShowsItsPage() async {
		let model = SettingsSamples.model()
		await model.load()
		model.handleDraft = " Matt-M "

		await model.saveProfile(isPublic: true)

		#expect(model.profile == ProfileSettings(handle: "matt-m", isPublic: true))
		#expect(model.profileURL?.absoluteString == "http://localhost:8000/matt-m")
	}
}

@MainActor
struct KeysModelTests {
	@Test func theSecretIsNotKeptAfterTheSheetCloses() async throws {
		let server = FakeAccountServer()
		let environment = SettingsSamples.environment(server)
		let model = KeysModel(environment: environment, server: SettingsSamples.server)
		await model.load()

		#expect(await model.create(kind: .mcp, name: "Amp"))
		let secret = try #require(model.created?.secret)
		#expect(model.keys.map(\.name).contains("Amp"))

		model.dismissSecret()

		#expect(model.created == nil)
		// Nothing the phone keeps holds it: not the listed keys, not the App Group, not the
		// app's defaults.
		let listed = try String(decoding: WireJSON.encoder().encode(model.keys), as: UTF8.self)
		#expect(!listed.contains(secret))
		let files = FileManager.default.enumerator(at: environment.shared.directory, includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL } ?? []
		for file in files {
			let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
			#expect(!contents.contains(secret), "\(file.lastPathComponent) holds the secret")
		}
		let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }
		#expect(!defaults.contains { $0.contains(secret) })
	}

	@Test func theClaudeCommandUsesTheMCPURLAndTheKey() {
		let model = KeysModel(environment: SettingsSamples.environment(FakeAccountServer()), server: URL(string: "https://feed-the-goose.mattjmcnaughton.com")!)
		#expect(model.mcpURL.absoluteString == "https://feed-the-goose.mattjmcnaughton.com/mcp")
		#expect(
			model.claudeCommand(secret: "ftg_abc")
				== "claude mcp add --transport http feed-the-goose https://feed-the-goose.mattjmcnaughton.com/mcp --header \"Authorization: Bearer ftg_abc\""
		)
	}

	@Test func aKeyNeedsAName() async {
		let server = FakeAccountServer()
		let model = KeysModel(environment: SettingsSamples.environment(server), server: SettingsSamples.server)
		await model.load()
		let before = model.keys.count

		#expect(await !model.create(kind: .api, name: "  "))
		#expect(model.problem != nil)
		#expect(await server.keyList.count == before)
	}
}
