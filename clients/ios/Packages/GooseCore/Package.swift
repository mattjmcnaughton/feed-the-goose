// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "GooseCore",
	platforms: [.iOS(.v26), .macOS(.v26)],
	products: [
		.library(name: "GooseCore", targets: ["GooseCore"]),
	],
	targets: [
		.target(name: "GooseCore"),
		.testTarget(name: "GooseCoreTests", dependencies: ["GooseCore"]),
	]
)
