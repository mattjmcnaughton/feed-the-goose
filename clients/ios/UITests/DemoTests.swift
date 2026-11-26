import XCTest

/// The end-to-end demo (TDD §8, ticket T20): one test per scene of the storyboard, run one at a
/// time by `scripts/demo/scene.sh`, which records each to its own clip. Every frame is the real
/// app talking to the orb's backend through the forwarded port. The scenes seed their users with
/// `POST /dev/seed`; nothing here is a fixture (constitution §1).
///
/// Skipped unless `FTG_DEMO=1`, so `just ios-uitest` does not run it. The scenes run in order on
/// one erased simulator: each starts where the last one left the app and the Home Screen.
///
/// A step that happens outside the phone, such as stopping the web service, is a cue: the test
/// writes `cue-<name>` to `$FTG_DEMO_DIR` (default `/tmp/ftg-demo`) and waits for `go-<name>`.
/// `docs/technical/demo.md` lists what to do at each cue.
@MainActor
final class DemoTests: XCTestCase {
	let app = XCUIApplication()
	let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
	let api = DemoAPI(base: URL(string: "http://localhost:8000")!)
	let dir = ProcessInfo.processInfo.environment["FTG_DEMO_DIR"] ?? "/tmp/ftg-demo"

	override func setUp() async throws {
		guard ProcessInfo.processInfo.environment["FTG_DEMO"] == "1" else {
			throw XCTSkip("The demo runs only from scripts/demo/scene.sh.")
		}
		continueAfterFailure = false
		guard await api.ready() else {
			throw XCTSkip("No backend at localhost:8000; see docs/technical/demo.md.")
		}
		try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		cue("record", timeout: 30) // scene.sh starts the clip here
	}

	// MARK: - Scenes

	/// Scene 1 (S1, S2): dev sign-in as a fresh account, then three habits.
	func test1SignInAndSetUp() async throws {
		try await api.signOutEveryone()
		try await api.seed("fresh", email: Demo.fresh)
		app.launch()
		try signIn(Demo.fresh)
		XCTAssertTrue(app.staticTexts["habits.empty"].waitForExistence(timeout: 15), "a fresh account lands on habit setup")
		pause(2)
		addHabit("Pushups", "reps", "50", "10")
		addHabit("Workout", "minutes", "30", "10")
		addHabit("Reading", "pages", "20", "5")
		pause(2)
		saveScreenshot("01-habit-setup")
		app.buttons["habitSetup.done"].tap()
		XCTAssertTrue(app.staticTexts["today.headline"].waitForExistence(timeout: 15))
		XCTAssertTrue(app.buttons["today.name.Reading"].waitForLabel("Reading, 0 of 20 pages"))
		pause(4)
		saveScreenshot("today-nothing-logged")
	}

	/// Scene 2 (S3, S4): the seeded `demo` account, lead 80. "+10" plays Snap and raises the lead;
	/// Undo takes it back; "+10" again.
	func test2LogAndUndo() async throws {
		try await api.signOutEveryone()
		try await api.seed("demo", email: Demo.matt)
		app.launch()
		try signIn(Demo.matt)
		let headline = app.staticTexts["today.headline"]
		XCTAssertTrue(headline.waitForExistence(timeout: 15))
		let pushups = app.buttons["today.name.Pushups"]
		XCTAssertTrue(pushups.waitForLabel("Pushups, 20 of 50 reps"), pushups.label)
		let start = try XCTUnwrap(lead(headline), headline.label)
		XCTAssertEqual(Double(start), 80, accuracy: 1, "the demo seed's lead")
		pause(3)
		saveScreenshot("today-part-logged")

		app.buttons["today.chunk.Pushups"].tap()
		XCTAssertTrue(pushups.waitForLabel("Pushups, 30 of 50 reps"), pushups.label)
		XCTAssertTrue(waitFor { (self.lead(headline) ?? 0) > start }, headline.label)
		pause(1)
		saveScreenshot("02-snap")
		pause(3)

		app.buttons["today.undo"].tap()
		XCTAssertTrue(pushups.waitForLabel("Pushups, 20 of 50 reps"), pushups.label)
		XCTAssertTrue(app.staticTexts["today.line"].label.hasPrefix("Took back 10 reps"), app.staticTexts["today.line"].label)
		pause(3)
		saveScreenshot("02-undone")

		app.buttons["today.chunk.Pushups"].tap()
		XCTAssertTrue(pushups.waitForLabel("Pushups, 30 of 50 reps"), pushups.label)
		pause(4)
	}

	/// Scene 3 (S8): the Chase and Feed widgets on the Home Screen; "+5 reading" on the Feed
	/// widget logs without opening the app, and both widgets redraw.
	func test3Widgets() async throws {
		app.launch()
		XCTAssertTrue(app.staticTexts["today.headline"].waitForExistence(timeout: 15))
		pause(1)
		XCUIDevice.shared.press(.home)
		sleep(1)
		XCUIDevice.shared.press(.home)
		sleep(1)
		addMediumWidget(title: "Chase")
		addMediumWidget(title: "Feed")
		let done = sb.buttons["Done"].firstMatch
		if done.waitForExistence(timeout: 3) { done.tap() } else { XCUIDevice.shared.press(.home) }

		XCTAssertTrue(waitFor(timeout: 20) { self.widgetLead() != nil }, sb.debugDescription)
		let before = try XCTUnwrap(widgetLead())
		pause(3)
		saveScreenshot("widgets-home-screen")

		let feed = sb.buttons["+5 reading"].firstMatch
		XCTAssertTrue(feed.waitForExistence(timeout: 5), sb.debugDescription)
		feed.tap()
		// 5 of 20 pages is a quarter of a third of 100 steps: 8.3 more.
		XCTAssertTrue(waitFor(timeout: 20) { (self.widgetLead() ?? 0) >= before + 6 && self.chaseWidgetShows((self.widgetLead() ?? 0)) },
		              "both widgets redraw: \(sb.debugDescription)")
		XCTAssertNotEqual(app.state, .runningForeground, "the app stayed closed")
		pause(4)
		saveScreenshot("widgets-after-feed")
	}

	/// Scene 4 (S13): an MCP key made in Settings; an MCP client outside the phone calls
	/// `log_habit` at `/mcp`; the app, brought forward, shows the log.
	func test4MCP() async throws {
		app.launch()
		XCTAssertTrue(app.staticTexts["today.headline"].waitForExistence(timeout: 15))
		let reading = app.buttons["today.name.Reading"]
		XCTAssertTrue(reading.waitForLabel("Reading, 5 of 20 pages"), reading.label)
		pause(2)
		app.tabBars.buttons["Settings"].tap()
		dismissZonePrompt()
		scroll(to: app.buttons["settings.keys"]).tap()
		app.buttons["keys.new"].tap()
		let name = app.textFields["newKey.name"]
		XCTAssertTrue(name.waitForExistence(timeout: 5))
		name.tap()
		name.typeText("Claude Code")
		app.buttons["newKey.create"].tap()
		let secret = app.staticTexts["secret.value"]
		XCTAssertTrue(secret.waitForExistence(timeout: 10))
		// The MCP client on the orb needs the key; it is shown once, here.
		try secret.label.write(toFile: "\(dir)/mcp-key", atomically: true, encoding: .utf8)
		pause(4)
		saveScreenshot("settings-mcp-key")
		app.buttons["secret.done"].tap()
		XCTAssertTrue(app.descendants(matching: .any)["key.Claude Code"].waitForExistence(timeout: 5))
		pause(2)
		app.navigationBars.buttons.element(boundBy: 0).tap()
		app.tabBars.buttons["Today"].tap()
		pause(2)
		XCUIDevice.shared.press(.home)
		pause(2)

		cue("mcp") // the orb runs scripts/demo/orb.sh mcp: tools/list, then log_habit 5 pages
		app.activate()
		XCTAssertTrue(reading.waitForLabel("Reading, 10 of 20 pages", timeout: 15), "the MCP log appears: \(reading.label)")
		pause(4)
		saveScreenshot("04-after-mcp")
	}

	/// Scene 5 (S5, S11): finishing the last two habits plays Feast, and the streak reaches 14.
	func test5Fed() async throws {
		app.launch()
		let headline = app.staticTexts["today.headline"]
		XCTAssertTrue(headline.waitForExistence(timeout: 15))
		XCTAssertTrue(app.staticTexts["today.streak"].label.hasPrefix("13"), app.staticTexts["today.streak"].label)
		pause(2)
		app.buttons["today.finish.Pushups"].tap()
		XCTAssertTrue(app.staticTexts["Pushups done"].waitForExistence(timeout: 10))
		pause(3)
		app.buttons["today.finish.Reading"].tap()
		XCTAssertTrue(headline.waitForLabel("The goose is fed", timeout: 15), headline.label)
		XCTAssertTrue(app.staticTexts["today.streak"].waitForLabel(prefix: "14"), app.staticTexts["today.streak"].label)
		pause(2)
		saveScreenshot("05-feast")
		pause(8)
		saveScreenshot("today-complete")
	}

	/// Not a scene: Settings, section by section, for the gallery.
	func test5bSettingsGallery() {
		app.launch()
		XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
		app.tabBars.buttons["Settings"].tap()
		dismissZonePrompt()
		XCTAssertTrue(app.buttons["day.edit"].waitForExistence(timeout: 10))
		sleep(2)
		saveScreenshot("settings-1-day-and-reminders")
		scroll(to: app.switches["profile.public"])
		sleep(1)
		saveScreenshot("settings-2-profile")
		scroll(to: app.buttons["settings.signOut"])
		sleep(1)
		saveScreenshot("settings-3-keys-devices-account")
		app.buttons["settings.keys"].tap()
		XCTAssertTrue(app.descendants(matching: .any)["key.Claude Code"].waitForExistence(timeout: 5))
		sleep(1)
		saveScreenshot("settings-4-keys")
	}

	/// Not a scene: the app's actions in the Shortcuts app, for the gallery.
	func test5cShortcutsGallery() {
		let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
		shortcuts.launch()
		for label in ["Continue", "Not Now", "Get Started"] {
			let button = shortcuts.buttons[label]
			if button.waitForExistence(timeout: 2) { button.tap() }
		}
		// A new shortcut, then the action search, filtered to the app.
		let add = shortcuts.buttons.matching(NSPredicate(format: "label IN %@", ["Add", "New Shortcut", "Create Shortcut"])).firstMatch
		XCTAssertTrue(add.waitForExistence(timeout: 10), shortcuts.debugDescription)
		add.tap()
		let search = shortcuts.searchFields.firstMatch
		if !search.waitForExistence(timeout: 5) {
			let addAction = shortcuts.buttons.matching(NSPredicate(format: "label CONTAINS 'Action'")).firstMatch
			XCTAssertTrue(addAction.waitForExistence(timeout: 5), shortcuts.debugDescription)
			addAction.tap()
		}
		XCTAssertTrue(search.waitForExistence(timeout: 5), shortcuts.debugDescription)
		search.tap()
		search.typeText("Feed the Goose")
		sleep(3)
		XCTAssertTrue(shortcuts.staticTexts["Log a habit"].waitForExistence(timeout: 10)
			|| shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'undo'")).firstMatch.exists,
			shortcuts.debugDescription)
		saveScreenshot("shortcuts-actions")
	}

	/// Scene 7 (S6): a seeded `caught-soon` account, caught about a minute after seeding: Peck.
	func test7Caught() async throws {
		try await api.signOutEveryone()
		try await api.seed("caught-soon", email: Demo.caught, delay: 60)
		app.launch()
		try signIn(Demo.caught)
		let headline = app.staticTexts["today.headline"]
		XCTAssertTrue(headline.waitForExistence(timeout: 15))
		pause(3)
		saveScreenshot("today-low-lead")
		XCTAssertTrue(headline.waitForLabel("The goose got you", timeout: 120), headline.label)
		pause(1)
		saveScreenshot("07-peck")
		pause(8)
		saveScreenshot("today-caught")
	}

	/// Scene 8 (S10): the web service stops; a log is queued with its time; the service comes
	/// back and the log is sent, keeping the time it was made.
	func test8Offline() async throws {
		try await api.signOutEveryone()
		try await api.seed("almost-complete", email: Demo.offline)
		app.launch()
		try signIn(Demo.offline)
		let pushups = app.buttons["today.name.Pushups"]
		XCTAssertTrue(pushups.waitForLabel("Pushups, 40 of 50 reps", timeout: 15), pushups.label)
		pause(2)

		cue("offline") // the orb stops the web service
		let loggedAt = Date()
		app.buttons["today.finish.Pushups"].tap()
		XCTAssertTrue(app.descendants(matching: .any)["today.waiting"].waitForExistence(timeout: 90), "the log is queued")
		try ISO8601DateFormatter().string(from: loggedAt).write(toFile: "\(dir)/offline-logged-at", atomically: true, encoding: .utf8)
		pause(5)
		saveScreenshot("today-queued-offline")

		cue("online") // the orb starts the web service again
		app.swipeDown()
		XCTAssertTrue(waitFor(timeout: 90) { !self.app.descendants(matching: .any)["today.waiting"].exists }, "the queued log is sent")
		XCTAssertTrue(app.staticTexts["Pushups done"].waitForExistence(timeout: 10))
		pause(4)
		saveScreenshot("08-delivered")
	}

	/// Scene 9 (S14): reminders on; the worker plans one and the recording sender captures it;
	/// `scripts/demo/scene.sh` delivers its payload with `xcrun simctl push`, not APNs.
	func test9Reminder() async throws {
		try await api.signOutEveryone()
		try await api.seed("caught-soon", email: Demo.remind, delay: 150)
		app.launch()
		try signIn(Demo.remind)
		XCTAssertTrue(app.staticTexts["today.headline"].waitForExistence(timeout: 15))
		pause(2)
		app.tabBars.buttons["Settings"].tap()
		dismissZonePrompt()
		let reminders = app.switches["reminders.enabled"]
		XCTAssertTrue(reminders.waitForExistence(timeout: 10))
		reminders.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
		let allow = sb.buttons["Allow"]
		if allow.waitForExistence(timeout: 10) { allow.tap() }
		XCTAssertTrue(waitFor(timeout: 20) { self.app.staticTexts["reminders.notice"].exists || self.app.descendants(matching: .any)["reminders.threshold"].exists })
		pause(3)
		saveScreenshot("settings-reminders-on")
		// The simulator issues no push token without a signing team, so this installation is
		// registered through the API with a stand-in token, which the recording sender accepts.
		let token = try await api.session(email: Demo.remind)
		try await api.registerDevice(token, installationID: UUID(), apnsToken: String(repeating: "0", count: 64))
		XCUIDevice.shared.press(.home)
		pause(2)

		cue("push", timeout: 240) // scene.sh reads GET /dev/pushes and runs xcrun simctl push
		let payload = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/push.json"))
		let aps = try XCTUnwrap((JSONSerialization.jsonObject(with: payload) as? [String: Any])?["aps"] as? [String: Any])
		let alert = aps["alert"] as? [String: Any]
		let title = try XCTUnwrap(alert?["title"] as? String ?? alert?["body"] as? String)
		let banner = sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
		XCTAssertTrue(banner.waitForExistence(timeout: 20), "the reminder shows: \(sb.debugDescription)")
		pause(1)
		saveScreenshot("09-reminder")
		pause(5)
	}

	// MARK: - Steps

	/// Throws when the app is not on sign-in, so the scene stops instead of going on as
	/// another account.
	private func signIn(_ email: String) throws {
		let field = app.textFields["signIn.email"]
		guard field.waitForExistence(timeout: 20) else {
			throw DemoError("the app is not signed out: \(app.debugDescription)")
		}
		pause(1)
		field.tap()
		field.typeText(email)
		pause(1)
		app.buttons["signIn.submit"].tap()
	}

	private func addHabit(_ name: String, _ unit: String, _ target: String, _ chunk: String) {
		app.buttons["habits.add"].tap()
		for (field, text) in [("name", name), ("unit", unit), ("target", target), ("chunk", chunk)] {
			let input = app.textFields["habitForm.\(field)"]
			XCTAssertTrue(input.waitForExistence(timeout: 5))
			input.tap()
			input.typeText(text)
		}
		app.buttons["habitForm.save"].tap()
		XCTAssertTrue(app.buttons["habit.\(name)"].waitForExistence(timeout: 10), "the server saved \(name)")
		pause(1)
	}

	private func dismissZonePrompt() {
		if app.buttons["zone.notNow"].waitForExistence(timeout: 2) { app.buttons["zone.notNow"].tap() }
	}

	/// Swipes the list until `element` is on screen; Settings is a lazy list.
	@discardableResult
	private func scroll(to element: XCUIElement) -> XCUIElement {
		for _ in 0 ..< 6 where !(element.exists && element.isHittable) {
			app.swipeUp()
		}
		XCTAssertTrue(element.waitForExistence(timeout: 5))
		return element
	}

	/// Writes `cue-<name>` and waits for `go-<name>`, which whoever runs the demo writes once
	/// they have done the step outside the phone.
	private func cue(_ name: String, timeout: TimeInterval = 300) {
		let go = "\(dir)/go-\(name)"
		try? FileManager.default.removeItem(atPath: go)
		FileManager.default.createFile(atPath: "\(dir)/cue-\(name)", contents: nil)
		XCTAssertTrue(waitFor(timeout: timeout) { FileManager.default.fileExists(atPath: go) }, "no go-\(name) in \(dir)")
		try? FileManager.default.removeItem(atPath: "\(dir)/cue-\(name)")
		try? FileManager.default.removeItem(atPath: go)
	}

	/// Holds the shot so the recording shows it.
	private func pause(_ seconds: UInt32) { sleep(seconds) }

	private func waitFor(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
		let end = Date().addingTimeInterval(timeout)
		repeat {
			if condition() { return true }
			RunLoop.current.run(until: Date().addingTimeInterval(0.5))
		} while Date() < end
		return false
	}

	/// The number in "N steps behind you".
	private func lead(_ headline: XCUIElement) -> Int? {
		Int(headline.label.split(separator: " ").first ?? "")
	}

	// MARK: - Widgets, as in WidgetTests

	/// The Feed widget's headline, "N steps".
	private func widgetLead() -> Int? {
		let text = sb.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ steps$")).firstMatch
		guard text.exists else { return nil }
		return Int(text.label.split(separator: " ").first ?? "")
	}

	/// The Chase widget is one combined element, the only one that names the stage.
	private func chaseWidgetShows(_ lead: Int) -> Bool {
		sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Big goose' AND label CONTAINS %@", "\(lead) steps")).firstMatch.exists
	}

	/// Opens the gallery, finds the app, swipes to the widget titled `title`, then once more to
	/// its medium size, and adds it. Stays in edit mode.
	private func addMediumWidget(title: String) {
		if !sb.buttons["Edit"].exists {
			sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 2)
			sleep(1)
		}
		for label in ["Edit", "Add Widget"] {
			let button = sb.buttons[label]
			if button.waitForExistence(timeout: 3) { button.tap(); sleep(1) }
		}
		let search = sb.searchFields.firstMatch
		XCTAssertTrue(search.waitForExistence(timeout: 5), sb.debugDescription)
		search.tap()
		search.typeText("Feed the Goose")
		sleep(2)
		sb.staticTexts["Feed the Goose"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
		sleep(3)
		for _ in 0 ..< 6 where !sb.staticTexts[title].exists { swipeGallery() }
		swipeGallery()
		XCTAssertTrue(sb.staticTexts[title].exists, "the gallery shows \(title)")
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
		sleep(3)
	}

	private func swipeGallery() {
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
			.press(forDuration: 0.05, thenDragTo: sb.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45)))
		sleep(2)
	}
}

struct DemoError: Error, CustomStringConvertible {
	let description: String
	init(_ description: String) { self.description = description }
}

/// The demo's accounts. Each must be in the backend's `ALLOWED_EMAILS`.
enum Demo {
	static var all: [String] { [fresh, matt, caught, offline, remind] }
	static let fresh = "new@example.com"
	static let matt = "matt@example.com"
	static let caught = "caught@example.com"
	static let offline = "offline@example.com"
	static let remind = "remind@example.com"
}

extension XCUIElement {
	func waitForLabel(prefix: String, timeout: TimeInterval = 10) -> Bool {
		let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: self)
		return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
	}
}

/// The backend calls the demo makes for itself: seeding, and what the simulator cannot do.
@MainActor
struct DemoAPI {
	let base: URL

	func ready() async -> Bool {
		(try? await send("GET", "readyz").status) == 200
	}

	func seed(_ scenario: String, email: String, delay: Int? = nil) async throws {
		var body: [String: Any] = ["scenario": scenario, "email": email]
		if let delay { body["delay_seconds"] = delay }
		let reply = try await send("POST", "dev/seed", body: body)
		XCTAssertEqual(reply.status, 200, String(decoding: reply.data, as: UTF8.self))
	}

	/// A session for the email, creating the account if it has none.
	func session(email: String) async throws -> String {
		let token = try await send("POST", "dev/token", body: ["email": email])
		let identity = try (JSONSerialization.jsonObject(with: token.data) as? [String: Any])?["identity_token"] as? String
		let reply = try await send("POST", "v1/auth/session", body: [
			"auth0_access_token": identity ?? "", "time_zone": TimeZone.current.identifier, "device_name": "DemoTests",
		])
		let signedIn = try JSONSerialization.jsonObject(with: reply.data) as? [String: Any]
		return try XCTUnwrap(signedIn?["session_token"] as? String, "sign-in refused; is \(email) in ALLOWED_EMAILS?")
	}

	/// Signs out every device of the account, so the app opens on sign-in for the next one.
	func revokeSessions(email: String) async throws {
		struct Session: Decodable { let id: String; let current: Bool }
		let token = try await session(email: email)
		let list = try await send("GET", "v1/auth/sessions", token: token)
		let sessions = try JSONDecoder().decode([Session].self, from: list.data)
		for id in sessions.sorted(by: { !$0.current && $1.current }).map({ $0.current ? "current" : $0.id }) {
			let reply = try await send("DELETE", "v1/auth/sessions/\(id)", token: token)
			XCTAssertEqual(reply.status, 204, String(decoding: reply.data, as: UTF8.self))
		}
	}

	/// Signs out every demo account, so the app opens on sign-in whichever one it last had.
	func signOutEveryone() async throws {
		for email in Demo.all { try await revokeSessions(email: email) }
	}

	func registerDevice(_ token: String, installationID: UUID, apnsToken: String) async throws {
		let reply = try await send("PUT", "v1/me/devices/\(installationID.uuidString.lowercased())", token: token, body: [
			"apns_token": apnsToken, "environment": "sandbox", "app_version": "demo",
		])
		XCTAssertEqual(reply.status, 204, String(decoding: reply.data, as: UTF8.self))
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
