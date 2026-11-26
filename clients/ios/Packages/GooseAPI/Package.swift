// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "GooseAPI",
	platforms: [.iOS(.v26), .macOS(.v26)],
	products: [
		.library(name: "GooseAPI", targets: ["GooseAPI"]),
	],
	dependencies: [
		.package(path: "../GooseCore"),
		.package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.4"),
		.package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.4.0"),
	],
	targets: [
		.target(
			name: "GooseAPI",
			dependencies: [
				"GooseCore",
				.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
				.product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
			]
		),
		.testTarget(
			name: "GooseAPITests",
			dependencies: [
				"GooseAPI",
				"GooseCore",
				.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
			]
		),
	]
)
