import Foundation
import Security

/// Writes one value to the App Group and to the shared Keychain group, and reads it back from
/// another process. It proves that the app and the widget extension can share state. T13
/// replaces it with `SharedStore` and `SessionStore`.
public struct SharingProbe: Sendable {
	public enum Failure: Error, Equatable, CustomStringConvertible {
		case noContainer
		case missing
		case writeFailed
		case keychain(OSStatus)

		public var description: String {
			switch self {
			case .noContainer: "no App Group container"
			case .missing: "nothing written yet"
			case .writeFailed: "could not write the file"
			case let .keychain(status): "Keychain error \(status)"
			}
		}
	}

	public let appGroup: String
	public let keychainAccessGroup: String

	private static let fileName = "sharing-probe.txt"
	private static let service = "com.mattjmcnaughton.feedthegoose.sharing-probe"

	/// Reads the groups from the `FTGAppGroup` and `FTGKeychainAccessGroup` Info.plist keys,
	/// which the build fills in from the same settings as the entitlements.
	public init?(infoDictionary: [String: Any]?) {
		guard let appGroup = infoDictionary?["FTGAppGroup"] as? String, !appGroup.isEmpty,
		      let keychainAccessGroup = infoDictionary?["FTGKeychainAccessGroup"] as? String,
		      !keychainAccessGroup.isEmpty
		else { return nil }
		self.appGroup = appGroup
		self.keychainAccessGroup = keychainAccessGroup
	}

	public func write(_ value: String) -> (appGroup: Failure?, keychain: Failure?) {
		(writeAppGroup(value), writeKeychain(value))
	}

	public func readAppGroup() -> Result<String, Failure> {
		guard let url = fileURL else { return .failure(.noContainer) }
		guard let data = try? Data(contentsOf: url) else { return .failure(.missing) }
		return .success(String(decoding: data, as: UTF8.self))
	}

	public func readKeychain() -> Result<String, Failure> {
		var query = baseQuery
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		if status == errSecItemNotFound { return .failure(.missing) }
		guard status == errSecSuccess, let data = item as? Data else { return .failure(.keychain(status)) }
		return .success(String(decoding: data, as: UTF8.self))
	}

	private var fileURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
			.appending(path: Self.fileName)
	}

	private var baseQuery: [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: Self.service,
			kSecAttrAccount as String: "probe",
			kSecAttrAccessGroup as String: keychainAccessGroup,
		]
	}

	private func writeAppGroup(_ value: String) -> Failure? {
		guard let url = fileURL else { return .noContainer }
		do {
			try Data(value.utf8).write(to: url, options: .atomic)
			return nil
		} catch {
			return .writeFailed
		}
	}

	private func writeKeychain(_ value: String) -> Failure? {
		SecItemDelete(baseQuery as CFDictionary)
		var attributes = baseQuery
		attributes[kSecValueData as String] = Data(value.utf8)
		attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		let status = SecItemAdd(attributes as CFDictionary, nil)
		return status == errSecSuccess ? nil : .keychain(status)
	}
}
