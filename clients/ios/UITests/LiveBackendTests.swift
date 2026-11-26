import XCTest

/// The real app against the orb's backend through the forwarded port (TDD §3.2, §7): dev
/// sign-in as a new account, add a habit, log a chunk, and see the lead rise and the habit's
/// progress change. The server owns the rules (constitution §1), so nothing here is a fixture:
/// the test reads the same chase from `/v1/chase/today` and checks the screen against it.
///
/// Needs `just dev` with `live@example.com` in `ALLOWED_EMAILS`. Skipped when nothing answers
/// at `localhost:8000/readyz`; `scripts/live-test.sh` checks that first, so it never skips.
@MainActor
final class LiveBackendTests: XCTestCase {
	static let email = "live@example.com"
	let api = LiveAPI(base: URL(string: "http://localhost:8000")!)

	func testSignInAddHabitAndLogAChunk() async throws {
		continueAfterFailure = false
		guard await api.ready() else {
			throw XCTSkip("No backend at localhost:8000; run `just dev` in the orb and forward port 8000.")
		}
		// A new account each run: delete whatever the last run left.
		try await api.deleteAccount(email: Self.email)

		let app = XCUIApplication()
		app.launch()
		// The Keychain outlives the app, so leave it signed out for the next UI test, which expects
		// a fresh install. Revoking the sessions keeps the account and its log for inspection.
		addTeardownBlock { @MainActor in
			try await self.api.revokeSessions(email: Self.email)
			app.terminate()
			app.launch()
			XCTAssertTrue(app.textFields["signIn.email"].waitForExistence(timeout: 15), "the revoked session signs the app out")
			app.terminate()
		}

		let email = app.textFields["signIn.email"]
		XCTAssertTrue(email.waitForExistence(timeout: 15), "a fresh install opens on sign-in")
		email.tap()
		email.typeText(Self.email)
		app.buttons["signIn.submit"].tap()

		XCTAssertTrue(app.staticTexts["habits.empty"].waitForExistence(timeout: 15), "a new account lands on habit setup")
		app.buttons["habits.add"].tap()
		for (field, text) in [("name", "Pushups"), ("unit", "reps"), ("target", "50"), ("chunk", "10")] {
			let input = app.textFields["habitForm.\(field)"]
			XCTAssertTrue(input.waitForExistence(timeout: 5))
			input.tap()
			input.typeText(text)
		}
		app.buttons["habitForm.save"].tap()
		XCTAssertTrue(app.buttons["habit.Pushups"].waitForExistence(timeout: 10), "the server saved the habit")
		saveScreenshot("live-habit-added")
		app.buttons["habitSetup.done"].tap()

		let headline = app.staticTexts["today.headline"]
		XCTAssertTrue(headline.waitForExistence(timeout: 15))
		let progress = app.buttons["today.name.Pushups"]
		XCTAssertTrue(progress.waitForLabel("Pushups, 0 of 50 reps"), progress.label)
		let before = try XCTUnwrap(lead(headline), headline.label)
		saveScreenshot("live-today-before")
		sleep(2)

		app.buttons["today.chunk.Pushups"].tap()
		XCTAssertTrue(progress.waitForLabel("Pushups, 10 of 50 reps"), progress.label)
		let rose = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (self.lead(headline) ?? 0) > before }, object: nil)
		XCTAssertEqual(XCTWaiter().wait(for: [rose], timeout: 10), .completed, "\(headline.label) after \(before)")
		let after = try XCTUnwrap(lead(headline))
		sleep(2)
		saveScreenshot("live-today-after")

		// The server's chase is the one on screen.
		let token = try await api.session(email: Self.email)
		let chase = try await api.chase(token)
		XCTAssertEqual(chase.state, "running")
		let pushups = try XCTUnwrap(chase.habits.first)
		XCTAssertEqual(chase.habits.count, 1)
		XCTAssertEqual(pushups.name, "Pushups")
		XCTAssertEqual(pushups.logged, 10)
		// One habit is worth the whole 100 steps, so 10 of 50 earns a fifth of them.
		XCTAssertEqual(pushups.steps, 20, accuracy: 0.05)
		XCTAssertEqual(chase.earned, 20, accuracy: 0.05)
		XCTAssertEqual(chase.lead, Double(after), accuracy: 1, "the screen shows the server's lead")

		let logs = try await api.logs(token, date: chase.date)
		XCTAssertEqual(logs.count, 1)
		XCTAssertEqual(logs.first?.source, "app")
		XCTAssertEqual(logs.first?.amount, 10)
		XCTAssertEqual(logs.first?.habit_id, pushups.habit_id)

		// T05: a target change applies from tomorrow, so today's chase keeps the old target.
		try await api.setTarget(token, habit: pushups.habit_id, target: 60)
		let unchanged = try await api.chase(token)
		let still = try XCTUnwrap(unchanged.habits.first)
		XCTAssertEqual(still.target, 50, "today's target is unchanged")
		XCTAssertEqual(still.logged, 10)
		XCTAssertEqual(still.steps, pushups.steps)
		XCTAssertEqual(unchanged.earned, chase.earned)
		XCTAssertEqual(unchanged.state, "running")
		print("LIVE email=\(Self.email) date=\(chase.date) lead \(before) -> \(after), server lead \(chase.lead), earned \(chase.earned), log \(logs.first?.id ?? "?") source \(logs.first?.source ?? "?"), target after PATCH \(still.target)")
	}

	/// The number in "N steps behind you".
	func lead(_ headline: XCUIElement) -> Int? {
		Int(headline.label.split(separator: " ").first ?? "")
	}
}

/// The few backend calls the test makes for itself, with its own session.
@MainActor
struct LiveAPI {
	let base: URL

	struct Habit: Decodable { let habit_id: String; let name: String; let target: Int; let logged: Int; let steps: Double }
	struct Chase: Decodable { let date: String; let state: String; let lead: Double; let earned: Double; let habits: [Habit] }
	struct Log: Decodable { let id: String; let habit_id: String; let amount: Int; let source: String }

	func ready() async -> Bool {
		(try? await send("GET", "readyz").status) == 200
	}

	/// A session for the email, creating the account if it has none.
	func session(email: String) async throws -> String {
		let identity = try await json("POST", "dev/token", body: ["email": email])["identity_token"] as? String
		let signedIn = try await json("POST", "v1/auth/session", body: [
			"auth0_access_token": identity ?? "", "time_zone": TimeZone.current.identifier, "device_name": "LiveBackendTests",
		])
		return try XCTUnwrap(signedIn["session_token"] as? String, "sign-in refused; is \(email) in ALLOWED_EMAILS?")
	}

	func deleteAccount(email: String) async throws {
		let reply = try await send("DELETE", "v1/me", token: session(email: email))
		XCTAssertEqual(reply.status, 204)
	}

	/// Signs out every device of the account, this helper's own session last.
	func revokeSessions(email: String) async throws {
		struct Session: Decodable { let id: String; let current: Bool }
		let token = try await session(email: email)
		let sessions: [Session] = try await decode(send("GET", "v1/auth/sessions", token: token))
		for id in sessions.sorted(by: { !$0.current && $1.current }).map({ $0.current ? "current" : $0.id }) {
			let reply = try await send("DELETE", "v1/auth/sessions/\(id)", token: token)
			XCTAssertEqual(reply.status, 204, String(decoding: reply.data, as: UTF8.self))
		}
	}

	func chase(_ token: String) async throws -> Chase {
		try await decode(send("GET", "v1/chase/today", token: token))
	}

	func logs(_ token: String, date: String) async throws -> [Log] {
		try await decode(send("GET", "v1/logs?date=\(date)", token: token))
	}

	func setTarget(_ token: String, habit: String, target: Int) async throws {
		let reply = try await send("PATCH", "v1/habits/\(habit)", token: token, body: ["target": target])
		XCTAssertEqual(reply.status, 200, String(decoding: reply.data, as: UTF8.self))
	}

	private func json(_ method: String, _ path: String, body: [String: Any]) async throws -> [String: Any] {
		let reply = try await send(method, path, body: body)
		XCTAssertTrue((200 ..< 300).contains(reply.status), "\(method) /\(path): \(reply.status) \(String(decoding: reply.data, as: UTF8.self))")
		return try XCTUnwrap(JSONSerialization.jsonObject(with: reply.data) as? [String: Any])
	}

	private func decode<T: Decodable>(_ reply: (status: Int, data: Data)) throws -> T {
		XCTAssertEqual(reply.status, 200, String(decoding: reply.data, as: UTF8.self))
		return try JSONDecoder().decode(T.self, from: reply.data)
	}

	private func send(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> (status: Int, data: Data) {
		var request = URLRequest(url: URL(string: path, relativeTo: base)!, timeoutInterval: 10)
		request.httpMethod = method
		if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
		if let body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		}
		let (data, response) = try await URLSession.shared.data(for: request)
		return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
	}
}
