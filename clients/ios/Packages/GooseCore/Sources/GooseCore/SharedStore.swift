import Foundation

/// A chase and the device time it arrived, as cached in the App Group.
public struct ChaseSnapshot: Codable, Hashable, Sendable {
	public var chase: Chase
	public var receivedAt: Date
	/// Set when the last fetch failed: the chase is shown with its age, not as current
	/// (constitution §8).
	public var isOutOfDate: Bool

	public init(chase: Chase, receivedAt: Date, isOutOfDate: Bool = false) {
		self.chase = chase
		self.receivedAt = receivedAt
		self.isOutOfDate = isOutOfDate
	}

	public var clock: ChaseClock { ChaseClock(chase: chase, receivedAt: receivedAt) }
}

/// The files the app, the widget extension and the intents share in the App Group. Each value
/// is one file, written atomically, so separate processes need no lock.
public struct SharedStore: Sendable {
	public let directory: URL

	public init(directory: URL) {
		self.directory = directory
	}

	/// The App Group's container, or nil when the process lacks the entitlement.
	public init?(appGroup: String) {
		guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
			return nil
		}
		self.init(directory: url)
	}

	/// The retry queue's directory (TDD §6.6).
	public var queueDirectory: URL { directory.appending(path: "queue", directoryHint: .isDirectory) }

	public var chaseSnapshot: ChaseSnapshot? { read("chase.json") }
	public func setChaseSnapshot(_ snapshot: ChaseSnapshot?) { write(snapshot, to: "chase.json") }

	/// The habits, cached for the widgets and the intents.
	public var habits: [Habit]? { read("habits.json") }
	public func setHabits(_ habits: [Habit]?) { write(habits, to: "habits.json") }

	/// The day on which a clip last played on this device. One file per clip, so two processes
	/// recording different clips cannot overwrite each other.
	public func played(_ clip: Clip) -> LocalDate? { read("played-\(clip.rawValue).json") }
	public func setPlayed(_ clip: Clip, on date: LocalDate) { write(date, to: "played-\(clip.rawValue).json") }

	/// This installation's ID, created the first time it is asked for (TDD §6.9).
	public func installationID() -> UUID {
		if let id: UUID = read("installation-id.json") { return id }
		let id = UUID()
		write(id, to: "installation-id.json")
		return id
	}

	// MARK: - The fixtures switch

	/// Set by a debug app launched with `-FTGUseFixtures`, so that the widgets and the intents,
	/// which take no launch arguments, also run on the fake environment.
	public var usesFixtures: Bool {
		FileManager.default.fileExists(atPath: directory.appending(path: "use-fixtures").path)
	}

	public func setUsesFixtures(_ on: Bool) {
		let url = directory.appending(path: "use-fixtures")
		if on {
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			FileManager.default.createFile(atPath: url.path, contents: Data())
		} else {
			try? FileManager.default.removeItem(at: url)
		}
	}

	/// A store beside this one for the fake environment, so fixture data never mixes with the
	/// signed-in user's.
	public var fixtureStore: SharedStore { SharedStore(directory: directory.appending(path: "fixtures", directoryHint: .isDirectory)) }

	// MARK: - Files

	private func read<Value: Decodable>(_ name: String) -> Value? {
		guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
		return try? WireJSON.decoder().decode(Value.self, from: data)
	}

	private func write(_ value: (some Encodable)?, to name: String) {
		let url = directory.appending(path: name)
		guard let value else {
			try? FileManager.default.removeItem(at: url)
			return
		}
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try WireJSON.encoder().encode(value).write(to: url, options: .atomic)
		} catch {
			assertionFailure("SharedStore could not write \(name): \(error)")
		}
	}
}
