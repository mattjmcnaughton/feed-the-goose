import XCTest

private extension Data {
	// The simulator runner shares the Mac's file system, so screenshots can go straight to /tmp.
	func write(to path: String) { try? write(to: URL(fileURLWithPath: path)) }
}

/// Drives Springboard to put the Goose widget on the Home Screen, so it can be screenshotted.
final class AddWidgetTests: XCTestCase {
	func testAddWidget() throws {
		let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
		XCUIDevice.shared.press(.home)
		sleep(1)
		XCUIDevice.shared.press(.home)
		sleep(1)
		// Long-press an empty spot to enter jiggle mode.
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 2)
		sleep(1)
		for label in ["Edit", "Add Widget"] {
			let b = sb.buttons[label]
			if b.waitForExistence(timeout: 3) { b.tap(); sleep(1) }
		}
		let search = sb.searchFields.firstMatch
		XCTAssertTrue(search.waitForExistence(timeout: 5), sb.debugDescription)
		search.tap()
		search.typeText("Goose")
		sleep(2)
		// The gallery lists widgets under the app's name.
		// Springboard reports the row as not hittable, so tap its coordinate.
		sb.staticTexts["GooseSpike"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
		sleep(3)
		XCUIScreen.main.screenshot().pngRepresentation.write(to: "/tmp/out/widget-gallery.png")
		// The Add Widget button is not in Springboard's accessibility tree either.
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
		sleep(2)
		let done = sb.buttons["Done"].firstMatch
		if done.waitForExistence(timeout: 3) { done.tap() } else { XCUIDevice.shared.press(.home) }
		sleep(3)
	}
}
