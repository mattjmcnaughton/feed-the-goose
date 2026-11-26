import SnapshotTesting
import SwiftUI
import WidgetKit
import XCTest
@testable import FeedTheGoose

/// Each widget family in each state, at the iPhone 17 Pro's widget sizes, and the Home Screen
/// families again at a large Dynamic Type size (TDD §7). Reference images are recorded on the
/// pinned simulator; open them before reporting.
@MainActor
final class WidgetSnapshotTests: XCTestCase {
	static let sizes: [WidgetFamily: CGSize] = [
		.systemSmall: CGSize(width: 170, height: 170),
		.systemMedium: CGSize(width: 364, height: 170),
		.accessoryRectangular: CGSize(width: 172, height: 76),
		.accessoryCircular: CGSize(width: 76, height: 76),
	]

	func frame(_ view: some View, _ family: WidgetFamily, large: Bool = false) -> some View {
		let size = Self.sizes[family]!
		let accessory = family == .accessoryCircular || family == .accessoryRectangular
		return view
			.frame(width: size.width, height: size.height)
			.background(accessory ? Color.white.opacity(0.0) : WidgetStyle.paper)
			.clipShape(accessory ? AnyShape(Rectangle()) : AnyShape(RoundedRectangle(cornerRadius: 22)))
			.dynamicTypeSize(large ? .xxxLarge : .large)
			.padding(8)
			.background(accessory ? Color(white: 0.85) : Color(white: 0.92))
	}

	func check(_ view: some View, _ family: WidgetFamily, _ name: String, large: Bool = false, file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
		let size = Self.sizes[family]!
		assertSnapshot(
			of: frame(view, family, large: large),
			as: .image(perceptualPrecision: 0.98, layout: .fixed(width: size.width + 16, height: size.height + 16)),
			named: name, file: file, testName: testName, line: line
		)
	}

	func testChaseWidget() {
		for (state, entry) in WidgetFixtures.states {
			for family in [WidgetFamily.systemMedium, .systemSmall, .accessoryRectangular, .accessoryCircular] {
				check(ChaseWidgetView(entry: entry, family: family), family, "\(family)-\(state)")
			}
		}
	}

	func testFeedWidget() {
		for (state, entry) in WidgetFixtures.states {
			for family in [WidgetFamily.systemMedium, .systemSmall] {
				check(FeedWidgetView(entry: entry, family: family), family, "\(family)-\(state)")
			}
		}
	}

	func testLargeType() {
		for (state, entry) in WidgetFixtures.states where ["running", "out-of-date"].contains(state) {
			for family in [WidgetFamily.systemMedium, .systemSmall] {
				check(ChaseWidgetView(entry: entry, family: family), family, "chase-\(family)-\(state)", large: true)
				check(FeedWidgetView(entry: entry, family: family), family, "feed-\(family)-\(state)", large: true)
			}
		}
	}
}
