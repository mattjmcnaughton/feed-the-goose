import Foundation
import Security

/// The app session's token, shared by the app, the widget extension and the intents through a
/// Keychain access group (TDD §6.1). It is readable after first unlock, on this device only.
public final class SessionStore: Sendable {
	private enum Backing: Sendable {
		case keychain(service: String, accessGroup: String?)
		case memory(Locked<String?>)
	}

	private let backing: Backing

	/// The Keychain item in `accessGroup`. Pass nil for the process's default group.
	public init(service: String = "com.mattjmcnaughton.feedthegoose.session", accessGroup: String?) {
		backing = .keychain(service: service, accessGroup: accessGroup)
	}

	private init(memory token: String?) {
		backing = .memory(Locked(token))
	}

	/// A store that keeps the token in memory, for the fake environment and tests.
	public static func inMemory(token: String? = nil) -> SessionStore {
		SessionStore(memory: token)
	}

	/// The token, or nil when signed out. Throws when the Keychain cannot be read, such as before
	/// the first unlock after a restart, so a failure never looks like being signed out
	/// (constitution §8).
	public func token() throws(SessionStoreError) -> String? {
		switch backing {
		case let .memory(token):
			return token.value
		case .keychain:
			var query = keychainQuery
			query[kSecReturnData as String] = true
			query[kSecMatchLimit as String] = kSecMatchLimitOne
			var item: CFTypeRef?
			let status = SecItemCopyMatching(query as CFDictionary, &item)
			if status == errSecItemNotFound { return nil }
			guard status == errSecSuccess, let data = item as? Data else { throw SessionStoreError(status: status) }
			return String(decoding: data, as: UTF8.self)
		}
	}

	/// Saves the token, replacing any other in place, so another process never reads a gap.
	public func save(_ token: String) throws(SessionStoreError) {
		switch backing {
		case let .memory(stored):
			stored.value = token
		case .keychain:
			let data = Data(token.utf8)
			var status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
			if status == errSecItemNotFound {
				var attributes = keychainQuery
				attributes[kSecValueData as String] = data
				attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
				status = SecItemAdd(attributes as CFDictionary, nil)
			}
			guard status == errSecSuccess else { throw SessionStoreError(status: status) }
		}
	}

	/// Forgets the token: signing out.
	public func clear() {
		switch backing {
		case let .memory(stored): stored.value = nil
		case .keychain: SecItemDelete(keychainQuery as CFDictionary)
		}
	}

	private var keychainQuery: [String: Any] {
		guard case let .keychain(service, accessGroup) = backing else { return [:] }
		var query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: "app-session",
		]
		if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
		return query
	}
}

public struct SessionStoreError: Error, Hashable, Sendable {
	public let status: OSStatus
}

/// A value behind a lock.
final class Locked<Value: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private var stored: Value

	init(_ value: Value) { stored = value }

	var value: Value {
		get { lock.withLock { stored } }
		set { lock.withLock { stored = newValue } }
	}

	func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
		try lock.withLock { try body(&stored) }
	}
}
