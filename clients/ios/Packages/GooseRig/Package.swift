// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "GooseRig",
	platforms: [.iOS(.v26), .macOS(.v26)],
	products: [
		.library(name: "GooseRig", targets: ["GooseRig"]),
	],
	targets: [
		.target(name: "GooseRig"),
		.testTarget(name: "GooseRigTests", dependencies: ["GooseRig"]),
	]
)
