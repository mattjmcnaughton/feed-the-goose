// swift-tools-version: 6.2
// Pins swift-openapi-generator for `scripts/generate-api.sh`, which runs it as a command so
// that builds need no plugin trust. Nothing links against this package.
import PackageDescription

let package = Package(
	name: "GooseAPIGenerator",
	platforms: [.macOS(.v15)],
	dependencies: [
		.package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.4"),
	]
)
