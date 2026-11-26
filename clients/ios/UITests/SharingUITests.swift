import XCTest

/// Proves that the app and the widget extension share the App Group and the Keychain: the app
/// writes a fresh value to both, then the test puts the placeholder widget on the Home Screen,
/// which reads both. Springboard hides the widget gallery's controls from the accessibility
/// tree, so some taps are coordinates, as in `spikes/swiftui-goose/UITests/AddWidgetTests.swift`.
final class SharingUITests: XCTestCase {
	func testWidgetReadsWhatTheAppWrote() throws {
		let value = "probe-\(Int(Date().timeIntervalSince1970))"
		let app = XCUIApplication()
		app.launchArguments = ["-FTGSharingProbe", value]
		app.launch()
		XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))

		let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
		XCUIDevice.shared.press(.home)
		sleep(1)
		XCUIDevice.shared.press(.home)
		sleep(1)
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 2)
		sleep(1)
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
		saveScreenshot("sharing-gallery")
		sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
		sleep(2)
		let done = sb.buttons["Done"].firstMatch
		if done.waitForExistence(timeout: 3) { done.tap() } else { XCUIDevice.shared.press(.home) }
		sleep(3)

		// The widget's text is in Springboard's tree, so the value can be asserted, not only seen.
		let shown = sb.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value))
		XCTAssertTrue(shown.firstMatch.waitForExistence(timeout: 10), sb.debugDescription)
		XCTAssertEqual(shown.count, 2, "the widget should show the value from both stores")
		saveScreenshot("sharing-widget")
	}
}
