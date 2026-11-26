import XCTest

/// Today on the scripted server (`-FTGTodayScript`, debug builds with `-FTGUseFixtures`).
final class TodayUITests: XCTestCase {
	override func setUp() {
		continueAfterFailure = false
	}

	func launch(_ script: String) -> XCUIApplication {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGUseFixtures", "-FTGTodayScript", script]
		app.launch()
		XCTAssertTrue(app.staticTexts["today.headline"].waitForExistence(timeout: 10))
		return app
	}

	/// The steps in "N steps behind you".
	func lead(_ app: XCUIApplication) -> Int {
		Int(app.staticTexts["today.headline"].label.split(separator: " ").first ?? "") ?? -1
	}

	/// A log raises the lead, Undo takes it back, and finishing the last habit feeds the goose.
	func testLogUndoAndFinish() {
		let app = launch("day")
		let start = lead(app)
		XCTAssertEqual(start, 80, "the scripted day starts like the example day")
		sleep(2)

		app.buttons["today.chunk.Pushups"].tap()
		let line = app.staticTexts["today.line"]
		XCTAssertTrue(line.waitForExistence(timeout: 5))
		XCTAssertTrue(NSPredicate(format: "label BEGINSWITH '10 reps logged'").evaluate(with: line))
		XCTAssertEqual(lead(app), 87, "10 of 50 pushups is a fifth of a 33.3-step share")
		sleep(2)
		saveScreenshot("today-after-log")

		app.buttons["today.undo"].tap()
		XCTAssertTrue(app.staticTexts["today.headline"].waitForLabel("80 steps behind you"))
		sleep(2)

		app.buttons["today.finish.Pushups"].tap()
		sleep(2)
		app.buttons["today.finish.Reading"].tap()
		XCTAssertTrue(app.staticTexts["today.headline"].waitForLabel("The goose is fed"))
		XCTAssertFalse(app.buttons["today.finish.Reading"].exists, "the log buttons are gone")
		sleep(5)
		saveScreenshot("today-fed")
	}

	/// Doing nothing, the app learns of the catch at the time the server named.
	func testCatchPlaysPeck() {
		let app = launch("caught-soon")
		XCTAssertTrue(app.staticTexts["today.headline"].waitForLabel("The goose got you", timeout: 40))
		XCTAssertFalse(app.buttons["today.chunk.Pushups"].isEnabled, "a caught day takes no logs")
		sleep(4)
		saveScreenshot("today-caught")
	}

	func testAccessibilityAudit() throws {
		let app = launch("day")
		try audit(app)
		app.buttons["today.name.Pushups"].tap()
		XCTAssertTrue(app.buttons["today.logOther.Pushups"].waitForExistence(timeout: 5))
		sleep(2)
		saveScreenshot("today-other-amount")
		try audit(app)
	}

	/// Every audit type; each issue is printed with its element before the test fails.
	func audit(_ app: XCUIApplication) throws {
		try app.performAccessibilityAudit { issue in
			print("AUDIT \(issue.compactDescription) | \(issue.detailedDescription) :: \(issue.element?.debugDescription.prefix(300) ?? "nil")")
			return false
		}
	}
}

extension XCUIElement {
	func waitForLabel(_ label: String, timeout: TimeInterval = 10) -> Bool {
		let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: self)
		return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
	}
}
