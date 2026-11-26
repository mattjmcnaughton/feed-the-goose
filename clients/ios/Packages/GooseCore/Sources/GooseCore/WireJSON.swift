import Foundation

/// The JSON coding the API uses: snake_case keys and UTC timestamps to the second. The fakes
/// read the fixtures with it, and the App Group files are written with it.
public enum WireJSON {
	public static func decoder() -> JSONDecoder {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}

	public static func encoder() -> JSONEncoder {
		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .convertToSnakeCase
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.sortedKeys]
		return encoder
	}
}
