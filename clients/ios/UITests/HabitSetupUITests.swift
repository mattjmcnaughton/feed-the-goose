import XCTest

/// First-run habit setup on the fake environment with no habits: add three, move one, archive
/// one, then Done moves on to the chase.
final class HabitSetupUITests: XCTestCase {
	override func setUp() {
		continueAfterFailure = false
	}

	func testAddThreeReorderArchiveAndMoveOn() {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGUseFixtures", "-FTGFreshAccount"]
		app.launch()

		XCTAssertTrue(app.staticTexts["habits.empty"].waitForExistence(timeout: 10))
		saveScreenshot("habits-setup-empty")

		add(app, "Pushups", "reps", "50", "10")
		add(app, "Workout", "minutes", "30", "10")
		add(app, "Reading", "pages", "20", "5")
		XCTAssertTrue(app.staticTexts["Your habits · 3 of 8"].waitForExistence(timeout: 5))
		XCTAssertEqual(order(app), ["Pushups", "Workout", "Reading"])
		saveScreenshot("habits-setup-three")

		// Drag Reading to the top.
		app.buttons["habits.reorder"].tap()
		let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
		XCTAssertTrue(handles.element(boundBy: 2).waitForExistence(timeout: 5))
		handles.element(boundBy: 2).press(forDuration: 0.6, thenDragTo: handles.element(boundBy: 0))
		let moved = expectation(for: NSPredicate { _, _ in self.order(app) == ["Reading", "Pushups", "Workout"] }, evaluatedWith: nil)
		wait(for: [moved], timeout: 5)
		app.buttons["habits.reorder"].tap()
		saveScreenshot("habits-setup-reordered")

		// Archive Workout: it stays today and leaves tomorrow.
		app.buttons["habit.Workout"].swipeLeft()
		app.buttons["Archive"].tap()
		app.buttons["Archive from tomorrow"].tap()
		XCTAssertTrue(app.staticTexts["Your habits · 2 of 8"].waitForExistence(timeout: 5))
		XCTAssertTrue(app.buttons["habit.Workout"].label.contains("Archived from tomorrow"))
		saveScreenshot("habits-setup-archived")

		app.buttons["habitSetup.done"].tap()
		XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
	}

	private func add(_ app: XCUIApplication, _ name: String, _ unit: String, _ target: String, _ chunk: String) {
		app.buttons["habits.add"].tap()
		for (field, text) in [("name", name), ("unit", unit), ("target", target), ("chunk", chunk)] {
			let input = app.textFields["habitForm.\(field)"]
			XCTAssertTrue(input.waitForExistence(timeout: 5))
			input.tap()
			input.typeText(text)
		}
		app.buttons["habitForm.save"].tap()
		XCTAssertTrue(app.buttons["habit.\(name)"].waitForExistence(timeout: 5))
	}

	/// The habit rows' names, top to bottom.
	private func order(_ app: XCUIApplication) -> [String] {
		app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'habit.' AND NOT identifier CONTAINS '.notice'"))
			.allElementsBoundByIndex
			.sorted { $0.frame.minY < $1.frame.minY }
			.map { String($0.identifier.dropFirst("habit.".count)) }
	}
}
