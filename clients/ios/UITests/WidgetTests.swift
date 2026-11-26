import XCTest

/// Adds the Chase and the Feed widgets to the Home Screen on the fake environment, then taps
/// "+10 pushups" on the Feed widget and checks that both widgets redraw without the app opening.
/// Run on an erased simulator: Springboard keeps widgets between runs. The gallery's controls
/// are hidden from the accessibility tree, so some taps are coordinates, as in `SharingUITests`.
@MainActor
final class WidgetTests: XCTestCase {
	let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")

	func testBothWidgetsOnTheHomeScreenAndAFeedTap() throws {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGUseFixtures"]
		app.launch()
		XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))
		XCUIDevice.shared.press(.home)
		sleep(1)
		XCUIDevice.shared.press(.home)
		sleep(1)

		addMediumWidget(title: "Chase")
		addMediumWidget(title: "Feed")
		let done = sb.buttons["Done"].firstMatch
		if done.waitForExistence(timeout: 3) { done.tap() } else { XCUIDevice.shared.press(.home) }
		sleep(3)

		// The fixture chase: 80 steps behind you, on both widgets.
		XCTAssertTrue(bothShow("80 steps", timeout: 15), sb.debugDescription)
		saveScreenshot("widgets-added")

		// 10 of 50 pushups, a third of 100 steps: 6.7 more, so 87 steps on both widgets.
		let feed = sb.buttons["+10 pushups"].firstMatch
		XCTAssertTrue(feed.waitForExistence(timeout: 5), sb.debugDescription)
		sleep(2)
		feed.tap()
		XCTAssertTrue(bothShow("87 steps", timeout: 20), "both widgets redraw: \(sb.debugDescription)")
		XCTAssertNotEqual(app.state, .runningForeground, "the app stayed closed")
		sleep(2)
		saveScreenshot("widgets-after-feed")
	}

	/// The Chase widget is one combined element, the only one that names the stage; the Feed
	/// widget's headline is its own text.
	private func bothShow(_ lead: String, timeout: TimeInterval) -> Bool {
		let chase = sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Big goose' AND label CONTAINS %@", lead))
		let feed = sb.staticTexts.matching(NSPredicate(format: "label == %@", lead))
		let end = Date().addingTimeInterval(timeout)
		repeat {
			if chase.firstMatch.exists, feed.firstMatch.exists { return true }
			sleep(1)
		} while Date() < end
		return false
	}

	/// Opens the gallery, finds the app, swipes to the widget titled `title`, then once more to
	/// its medium size (each widget lists small first), and adds it. Stays in edit mode.
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
		XCTAssertTrue(sb.staticTexts[title].exists, "the gallery shows \(title): \(sb.staticTexts.allElementsBoundByIndex.map(\.label))")
		saveScreenshot("gallery-\(title.lowercased())")
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
		sleep(3)
	}

	private func swipeGallery() {
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
			.press(forDuration: 0.05, thenDragTo: sb.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45)))
		sleep(2)
	}
}
