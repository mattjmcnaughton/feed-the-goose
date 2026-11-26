import Foundation
import GooseAPI
import GooseCore
import Testing

/// Every exchange in `clients/fixtures/` runs through the generated client: the stub server
/// answers with the fixture's response, the live service adapts it to a GooseCore model, and
/// the model must equal the fixture's body decoded independently with `WireJSON`. The request
/// the client sent must match the fixture's request. A fixture with no route here fails.
struct FixtureContractTests {
	/// `clients/fixtures/`, read from the source tree, which the simulator shares with the Mac.
	static let sourceFixtures = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent().appending(path: "../../../../../fixtures").standardized

	@Test func theBundledFixturesAreEveryFixtureInTheContract() {
		let source = Fixtures.names(in: Self.sourceFixtures)
		#expect(source.count == 38)
		#expect(Fixtures.names() == source)
	}

	@Test(arguments: Fixtures.names(in: sourceFixtures))
	func fixtureDecodesThroughTheGeneratedClient(name: String) async throws {
		let fixture = try Fixtures.load(name, in: Self.sourceFixtures)
		let server = StubServer { _ in (fixture.status, fixture.responseBody) }
		let services = server.services()

		do {
			let handled = try await Self.exercise(fixture, services)
			#expect(handled, "No call decodes fixture \(name): add its route to exercise(_:_:)")
			#expect(fixture.status < 400, "\(name) answers \(fixture.status) but the call succeeded")
		} catch let error as APIError {
			#expect(fixture.status >= 400, "\(name) threw \(error)")
			#expect(error == (try Self.expectedError(fixture)))
		}

		let request = try #require(server.requests.first)
		#expect(request.method == fixture.method)
		#expect(request.path == fixture.path)
		let isPublic = fixture.path == "/v1/auth/session" || fixture.path.hasPrefix("/v1/profiles/")
		#expect(request.authorization == (isPublic ? nil : "Bearer test-session-token"))
		let sent = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? NSDictionary
		let expected = fixture.requestBody
			.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
			.map { $0.filter { !($0.value is NSNull) } as NSDictionary }
		#expect(sent == expected, "\(name) sent \(String(describing: sent))")
	}

	/// The APIError a fixture's problem body stands for, read from the fixture's JSON.
	static func expectedError(_ fixture: Fixture) throws -> APIError {
		struct Problem: Decodable {
			let type: String
			let errors: [FieldError]?
		}
		let problem = try fixture.response(as: Problem.self)
		switch problem.type {
		case "unauthenticated": return .unauthenticated
		case "identity_not_admitted": return .identityNotAdmitted
		case "not_found": return .notFound
		case "no_chase": return .noChase
		case "day_settled": return .daySettled
		case "handle_taken": return .handleTaken
		case "invalid": return .invalid(problem.errors ?? [])
		case "rate_limited": return .rateLimited
		case "not_implemented": return .notImplemented
		default: throw CocoaError(.coderInvalidValue)
		}
	}

	/// Makes the call the fixture's request describes and checks the adapted result. Returns
	/// false when no call matches the fixture's route.
	static func exercise(_ fixture: Fixture, _ services: LiveServices) async throws -> Bool {
		let parts = fixture.path.split(separator: "?", maxSplits: 1).map(String.init)
		let segments = parts[0].split(separator: "/").map(String.init)
		let query = Dictionary(
			(parts.count > 1 ? parts[1] : "").split(separator: "&").map {
				let pair = $0.split(separator: "=", maxSplits: 1).map(String.init)
				return (pair[0], pair.count > 1 ? pair[1] : "")
			},
			uniquingKeysWith: { first, _ in first }
		)
		let collections: Set = ["sessions", "habits", "logs", "devices", "keys", "profiles"]
		var route = segments
		var parameter = ""
		if route.count >= 3, collections.contains(route[route.count - 2]) {
			parameter = route[route.count - 1]
			route[route.count - 1] = "{}"
		}
		let id = UUID(uuidString: parameter) ?? UUID()

		func request<T: Decodable>(_ type: T.Type) throws -> T {
			try WireJSON.decoder().decode(type, from: fixture.requestBody ?? Data("null".utf8))
		}
		func check<T: Decodable & Equatable>(_ actual: T) throws {
			#expect(actual == (try fixture.response(as: T.self)), "\(fixture.name) adapted differently")
		}

		switch "\(fixture.method) /\(route.joined(separator: "/"))" {
		case "POST /v1/auth/session":
			struct SessionCreate: Decodable { let auth0AccessToken, timeZone, deviceName: String }
			let body = try request(SessionCreate.self)
			try check(await services.createSession(identityToken: body.auth0AccessToken, timeZone: body.timeZone, deviceName: body.deviceName))
		case "GET /v1/auth/sessions": try check(await services.sessions())
		case "DELETE /v1/auth/sessions/{}":
			try await services.deleteSession(parameter == "current" ? .current : .id(id))
		case "GET /v1/chase/today": try check(await services.today())
		case "GET /v1/days":
			try check(await services.days(from: LocalDate(rawValue: query["from"] ?? ""), to: LocalDate(rawValue: query["to"] ?? "")))
		case "GET /v1/habits": try check(await services.habits())
		case "POST /v1/habits": try check(await services.createHabit(request(HabitDraft.self)))
		case "PATCH /v1/habits/{}": try check(await services.updateHabit(id: id, request(HabitChanges.self)))
		case "DELETE /v1/habits/{}": try check(await services.archiveHabit(id: id))
		case "GET /v1/logs": try check(await services.logs(on: LocalDate(rawValue: query["date"] ?? "")))
		case "POST /v1/logs": try check(await services.createLog(request(LogRequest.self)))
		case "DELETE /v1/logs/{}": try check(await services.undoLog(id: id))
		case "GET /v1/me": try check(await services.account())
		case "PATCH /v1/me": try check(await services.updateAccount(request(AccountChanges.self)))
		case "DELETE /v1/me": try await services.deleteAccount()
		case "PUT /v1/me/devices/{}": try await services.registerDevice(installationID: id, request(DeviceRegistration.self))
		case "DELETE /v1/me/devices/{}": try await services.deleteDevice(installationID: id)
		case "GET /v1/me/keys": try check(await services.keys())
		case "POST /v1/me/keys":
			struct KeyCreate: Decodable { let kind: KeyKind; let name: String }
			let body = try request(KeyCreate.self)
			try check(await services.createKey(kind: body.kind, name: body.name))
		case "DELETE /v1/me/keys/{}": try await services.deleteKey(id: id)
		case "GET /v1/me/profile": try check(await services.profileSettings())
		case "PUT /v1/me/profile":
			let body = try request(ProfileSettings.self)
			try check(await services.updateProfileSettings(handle: body.handle ?? "", isPublic: body.isPublic))
		case "GET /v1/me/reminders": try check(await services.reminders())
		case "PUT /v1/me/reminders": try check(await services.updateReminders(request(Reminders.self)))
		case "GET /v1/profiles/{}": try check(await services.publicProfile(handle: parameter))
		default: return false
		}
		return true
	}
}
