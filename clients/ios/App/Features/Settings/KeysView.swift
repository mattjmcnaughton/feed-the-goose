import GooseCore
import SwiftUI
import UIKit

/// API keys and MCP keys: create one, see its secret once, revoke it.
struct KeysView: View {
	@State private var model: KeysModel
	@State private var creating = false

	init(model: KeysModel) {
		_model = State(initialValue: model)
	}

	var body: some View {
		List {
			if let problem = model.problem {
				Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
			}
			switch model.state {
			case .loading:
				ProgressView()
			case let .failed(message):
				Text(message).foregroundStyle(.secondary)
			case .loaded:
				Section {
					if model.keys.isEmpty {
						Text("No keys yet.").foregroundStyle(.secondary)
					}
					ForEach(model.keys) { key in
						KeyRow(key: key)
							.swipeActions {
								Button("Revoke", role: .destructive) { Task { await model.revoke(key) } }
							}
					}
				} footer: {
					Text("An API key works on the REST API. An MCP key works only at \(model.mcpURL.absoluteString), for tools such as Claude Code. Swipe a key to revoke it.")
				}
			}
		}
		.navigationTitle("Keys")
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button("New key", systemImage: "plus") { creating = true }
					.accessibilityIdentifier("keys.new")
			}
		}
		.sheet(isPresented: $creating) {
			NavigationStack { NewKeyForm(model: model) }
		}
		.sheet(isPresented: Binding(get: { model.created != nil }, set: { if !$0 { model.dismissSecret() } })) {
			if let created = model.created {
				NavigationStack { KeySecretView(created: created, command: model.claudeCommand(secret: created.secret), mcpURL: model.mcpURL) { model.dismissSecret() } }
					.interactiveDismissDisabled()
			}
		}
		.task { await model.load() }
		.refreshable { await model.load() }
		.accessibilityIdentifier("keys")
	}
}

private struct KeyRow: View {
	let key: Key

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(key.name).font(.body)
				Text(key.kind == .mcp ? "MCP" : "API")
					.font(.caption.weight(.semibold))
					.padding(.horizontal, 6).padding(.vertical, 1)
					.background(.quaternary, in: Capsule())
			}
			Text(lastUsed).font(.caption).foregroundStyle(.secondary)
		}
		.accessibilityElement(children: .combine)
		.accessibilityIdentifier("key.\(key.name)")
	}

	private var lastUsed: String {
		let created = "Created \(key.createdAt.formatted(date: .abbreviated, time: .omitted))"
		guard let used = key.lastUsedAt else { return "\(created) · never used" }
		return "\(created) · last used \(used.formatted(date: .abbreviated, time: .omitted))"
	}
}

private struct NewKeyForm: View {
	let model: KeysModel
	@Environment(\.dismiss) private var dismiss
	@State private var kind = KeyKind.mcp
	@State private var name = ""

	var body: some View {
		Form {
			Picker("Kind", selection: $kind) {
				Text("MCP").tag(KeyKind.mcp)
				Text("API").tag(KeyKind.api)
			}
			.pickerStyle(.segmented)
			.accessibilityIdentifier("newKey.kind")
			TextField("Name, such as Claude Code", text: $name)
				.accessibilityIdentifier("newKey.name")
			if let problem = model.problem {
				Text(problem).foregroundStyle(.red)
			}
		}
		.navigationTitle("New key")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
			ToolbarItem(placement: .confirmationAction) {
				Button("Create") {
					Task { if await model.create(kind: kind, name: name) { dismiss() } }
				}
				.disabled(model.working)
				.accessibilityIdentifier("newKey.create")
			}
		}
	}
}

/// A new key's secret, shown this once. Closing the sheet forgets it.
struct KeySecretView: View {
	let created: NewKey
	let command: String
	let mcpURL: URL
	let done: () -> Void
	@State private var copied: String?

	var body: some View {
		Form {
			Section {
				Text(created.secret)
					.font(.system(.callout, design: .monospaced))
					.textSelection(.enabled)
					.accessibilityIdentifier("secret.value")
				copyButton("Copy key", value: created.secret, id: "secret.copy")
			} header: {
				Text(created.key.name)
			} footer: {
				Text("This is the only time the key is shown. Copy it now; Feed the Goose keeps only a fingerprint of it.")
			}
			if created.key.kind == .mcp {
				Section {
					LabeledContent("MCP URL", value: mcpURL.absoluteString)
					Text(command)
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)
						.accessibilityIdentifier("secret.command")
					copyButton("Copy command", value: command, id: "secret.copyCommand")
				} header: {
					Text("Add it to Claude Code")
				}
			}
		}
		.navigationTitle("Your new key")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Done", action: done).accessibilityIdentifier("secret.done")
			}
		}
	}

	private func copyButton(_ title: String, value: String, id: String) -> some View {
		Button {
			UIPasteboard.general.string = value
			copied = id
		} label: {
			Label(copied == id ? "Copied" : title, systemImage: copied == id ? "checkmark" : "doc.on.doc")
		}
		.accessibilityIdentifier(id)
	}
}
