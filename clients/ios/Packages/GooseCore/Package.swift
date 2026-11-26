// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "GooseCore",
	platforms: [.iOS(.v26), .macOS(.v26)],
	products: [
		.library(name: "GooseCore", targets: ["GooseCore"]),
	],
	targets: [
		// `Fixtures` is a copy of clients/fixtures that scripts/generate-api.sh keeps in step.
		.target(name: "GooseCore", resources: [.copy("Fixtures")]),
		.testTarget(name: "GooseCoreTests", dependencies: ["GooseCore"]),
	]
)
