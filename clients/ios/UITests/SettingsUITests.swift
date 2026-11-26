import XCTest

/// Settings on the fake environment: the time zone prompt, changing the day's end, creating an
/// MCP key and copying its command, turning the profile on, and turning reminders on, which
/// shows whether the simulator issued a push token.
final class SettingsUITests: XCTestCase {
	override func setUp() {
		continueAfterFailure = false
	}

	private func openSettings(zone: String? = nil) -> XCUIApplication {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGUseFixtures"]
		if let zone { app.launchEnvironment["TZ"] = zone }
		app.launch()
		XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
		app.tabBars.buttons["Settings"].tap()
		XCTAssertTrue(app.buttons["day.edit"].waitForExistence(timeout: 10))
		return app
	}

	/// The phone's zone differs from the fixture account's America/New_York, so the app asks;
	/// "Not now" changes nothing.
	func testTheZonePromptChangesNothingOnNotNow() {
		let app = openSettings(zone: "Europe/Lisbon")
		XCTAssertTrue(app.buttons["zone.notNow"].waitForExistence(timeout: 5))
		saveScreenshot("settings-zone-prompt")
		app.buttons["zone.notNow"].tap()
		XCTAssertFalse(app.buttons["zone.notNow"].waitForExistence(timeout: 2))
		XCTAssertFalse(app.descendants(matching: .any)["day.pending"].exists)
		XCTAssertTrue(app.staticTexts["Time zone, America/New_York"].exists)
		saveScreenshot("settings-zone-not-now")
	}

	func testChangeTheDayEndCreateAnMCPKeyAndTurnTheProfileOn() {
		let app = openSettings()
		if app.buttons["zone.notNow"].waitForExistence(timeout: 2) { app.buttons["zone.notNow"].tap() }
		saveScreenshot("settings-top")

		// The day ends at 1:00 AM from tomorrow.
		app.buttons["day.edit"].tap()
		XCTAssertTrue(app.buttons["day.end"].waitForExistence(timeout: 5))
		app.buttons["day.end"].tap()
		// iOS puts a narrow no-break space before "AM".
		let oneAM = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^1:00.AM$")).firstMatch
		XCTAssertTrue(oneAM.waitForExistence(timeout: 5))
		oneAM.tap()
		app.buttons["day.save"].tap()
		XCTAssertTrue(app.descendants(matching: .any)["day.pending"].waitForExistence(timeout: 5))
		saveScreenshot("settings-day-pending")

		// An MCP key, shown once, and the command copied.
		scroll(app, to: app.buttons["settings.keys"]).tap()
		app.buttons["keys.new"].tap()
		let name = app.textFields["newKey.name"]
		XCTAssertTrue(name.waitForExistence(timeout: 5))
		name.tap()
		name.typeText("Amp")
		app.buttons["newKey.create"].tap()
		XCTAssertTrue(app.staticTexts["secret.value"].waitForExistence(timeout: 5))
		app.buttons["secret.copyCommand"].tap()
		XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 5))
		saveScreenshot("settings-key-secret")
		app.buttons["secret.done"].tap()
		XCTAssertTrue(app.descendants(matching: .any)["key.Amp"].waitForExistence(timeout: 5))
		XCTAssertFalse(app.staticTexts["secret.value"].exists)
		saveScreenshot("settings-keys")
		app.navigationBars.buttons.element(boundBy: 0).tap()

		// The profile on, with its page's address.
		let profile = scroll(app, to: app.switches["profile.public"])
		profile.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
		XCTAssertTrue(app.descendants(matching: .any)["profile.url"].waitForExistence(timeout: 5))
		saveScreenshot("settings-profile-on")
	}

	/// Turns reminders on and answers the permission alert. Whatever iOS does with the token,
	/// the screen says so; the capture is the evidence for TDD §6.9.
	func testTurningRemindersOnAsksForPermission() {
		let app = openSettings()
		if app.buttons["zone.notNow"].waitForExistence(timeout: 2) { app.buttons["zone.notNow"].tap() }
		let reminders = app.switches["reminders.enabled"]
		XCTAssertTrue(reminders.waitForExistence(timeout: 5))
		reminders.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
		let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
		let allow = springboard.buttons["Allow"]
		if allow.waitForExistence(timeout: 10) { allow.tap() }
		// Registered, or a notice that names iOS's reason; either way the switch settles.
		let settled = expectation(for: NSPredicate { _, _ in
			app.staticTexts["reminders.notice"].exists || app.buttons["reminders.threshold"].exists
				|| app.descendants(matching: .any)["reminders.threshold"].exists
		}, evaluatedWith: nil)
		wait(for: [settled], timeout: 20)
		sleep(1)
		let notice = app.staticTexts["reminders.notice"]
		print("FTGPushResult: \(notice.exists ? notice.label : "registered")")
		saveScreenshot("settings-reminders-on")
	}

	/// Swipes the list until `element` is on screen; Settings is a lazy list.
	@discardableResult
	private func scroll(_ app: XCUIApplication, to element: XCUIElement) -> XCUIElement {
		for _ in 0 ..< 6 where !(element.exists && element.isHittable) {
			app.swipeUp()
		}
		XCTAssertTrue(element.waitForExistence(timeout: 5))
		return element
	}
}
