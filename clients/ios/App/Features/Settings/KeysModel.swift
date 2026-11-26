import Foundation
import GooseCore
import Observation

/// API keys and MCP keys (PRD S13). A new key's secret is shown once, in a sheet, and the
/// model forgets it when the sheet closes: the server keeps only a digest, so nothing on the
/// phone can show it again.
@MainActor @Observable
final class KeysModel {
	enum State: Equatable {
		case loading
		case loaded
		case failed(String)
	}

	private(set) var state: State = .loading
	private(set) var keys: [Key] = []
	/// The key just created, with its secret, while its sheet is open.
	var created: NewKey?
	var problem: String?
	private(set) var working = false

	let environment: AppEnvironment
	let server: URL

	init(environment: AppEnvironment, server: URL) {
		self.environment = environment
		self.server = server
	}

	/// Where an MCP client connects.
	var mcpURL: URL { server.appending(path: "mcp") }

	/// The command that adds the server to Claude Code with this key.
	func claudeCommand(secret: String) -> String {
		"claude mcp add --transport http feed-the-goose \(mcpURL.absoluteString) --header \"Authorization: Bearer \(secret)\""
	}

	func load() async {
		do {
			keys = try await environment.account.keys()
			state = .loaded
		} catch {
			let message = SettingsModel.message(for: error)
			if state == .loaded { problem = message } else { state = .failed(message) }
		}
	}

	/// Creates a key and opens the sheet that shows its secret. Returns whether it did.
	func create(kind: KeyKind, name: String) async -> Bool {
		let name = name.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else {
			problem = "Give the key a name, such as the tool that will use it."
			return false
		}
		working = true
		defer { working = false }
		do {
			created = try await environment.account.createKey(kind: kind, name: name)
			problem = nil
		} catch {
			problem = SettingsModel.message(for: error)
			return false
		}
		await load()
		return true
	}

	/// The secret sheet closed: forget the secret.
	func dismissSecret() {
		created = nil
	}

	func revoke(_ key: Key) async {
		do {
			try await environment.account.deleteKey(id: key.id)
			problem = nil
		} catch {
			problem = SettingsModel.message(for: error)
		}
		await load()
	}
}
