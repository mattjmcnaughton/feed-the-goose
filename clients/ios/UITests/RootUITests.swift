import XCTest

/// Captures land in `FTG_CAPTURE_DIR` (default `/tmp/ftg-captures`): the simulator runner shares
/// the Mac's file system.
func saveScreenshot(_ name: String) {
	let dir = ProcessInfo.processInfo.environment["FTG_CAPTURE_DIR"] ?? "/tmp/ftg-captures"
	try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
	try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}

final class RootUITests: XCTestCase {
	func testRootListsEveryFeature() {
		let app = XCUIApplication()
		app.launch()
		for label in ["Sign in", "Habit setup", "Habits", "Today", "Settings"] {
			XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), label)
		}
		XCTAssertEqual(app.staticTexts["root.server"].label, "http://localhost:8000")
		saveScreenshot("root")
		app.buttons["Today"].tap()
		XCTAssertTrue(app.staticTexts["Built in T16."].waitForExistence(timeout: 5))
	}

	func testRigGalleryLaunchArgument() {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGRigGallery"]
		app.launch()
		XCTAssertTrue(app.staticTexts["Rig gallery"].waitForExistence(timeout: 5))
		saveScreenshot("rig-gallery")
	}
}
