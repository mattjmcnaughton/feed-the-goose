import XCTest

/// Captures land in `FTG_CAPTURE_DIR` (default `/tmp/ftg-captures`): the simulator runner shares
/// the Mac's file system.
func saveScreenshot(_ name: String) {
	let dir = ProcessInfo.processInfo.environment["FTG_CAPTURE_DIR"] ?? "/tmp/ftg-captures"
	try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
	try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}

final class RootUITests: XCTestCase {
	/// The fake environment is signed in with habits, so the app opens on the tabs.
	func testFixturesOpenOnTheTabs() {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGUseFixtures"]
		app.launch()
		XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
		XCTAssertTrue(app.staticTexts["today.headline"].waitForExistence(timeout: 5))
		saveScreenshot("root")
		app.tabBars.buttons["Settings"].tap()
		XCTAssertTrue(app.buttons["day.edit"].waitForExistence(timeout: 5))
	}

	func testRigGalleryLaunchArgument() {
		let app = XCUIApplication()
		app.launchArguments = ["-FTGRigGallery"]
		app.launch()
		XCTAssertTrue(app.staticTexts["Rig gallery"].waitForExistence(timeout: 5))
		saveScreenshot("rig-gallery")
	}
}
