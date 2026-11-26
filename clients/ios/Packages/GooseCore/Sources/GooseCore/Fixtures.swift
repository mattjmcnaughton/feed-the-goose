import Foundation

/// One exchange from `clients/fixtures/`, the contract's examples. The package bundles a copy
/// that `scripts/generate-api.sh` keeps in step, so the fakes read the same exchanges the
/// Python tests check.
public struct Fixture: Sendable {
	public let name: String
	public let method: String
	/// The path with its query, such as `/v1/logs?date=2026-11-26`.
	public let path: String
	/// The request's JSON body, or nil.
	public let requestBody: Data?
	public let status: Int
	/// The response's JSON body, or nil.
	public let responseBody: Data?

	/// The response body, decoded as the app's model.
	public func response<Value: Decodable>(as type: Value.Type = Value.self) throws -> Value {
		try WireJSON.decoder().decode(type, from: responseBody ?? Data("null".utf8))
	}
}

public enum Fixtures {
	/// The folder the fixtures are bundled in.
	public static var bundled: URL {
		guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
			preconditionFailure("GooseCore is missing its bundled fixtures")
		}
		return url
	}

	/// The name of every fixture in `directory`, sorted.
	public static func names(in directory: URL = bundled) -> [String] {
		let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
		return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
	}

	public static func load(_ name: String, in directory: URL = bundled) throws -> Fixture {
		let data = try Data(contentsOf: directory.appending(path: "\(name).json"))
		guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let request = object["request"] as? [String: Any],
		      let response = object["response"] as? [String: Any],
		      let method = request["method"] as? String,
		      let path = request["path"] as? String,
		      let status = response["status"] as? Int
		else { throw CocoaError(.coderReadCorrupt) }
		return Fixture(
			name: name,
			method: method,
			path: path,
			requestBody: try body(request["body"]),
			status: status,
			responseBody: try body(response["body"])
		)
	}

	/// The response of a fixture that the package ships, decoded. Only for the fakes.
	static func response<Value: Decodable>(_ name: String, as type: Value.Type = Value.self) -> Value {
		do {
			return try load(name).response(as: type)
		} catch {
			preconditionFailure("Fixture \(name) does not decode as \(type): \(error)")
		}
	}

	private static func body(_ value: Any?) throws -> Data? {
		guard let value, !(value is NSNull) else { return nil }
		return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
	}
}
