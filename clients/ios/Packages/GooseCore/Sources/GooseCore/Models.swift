import Foundation

// The app's own models. They mirror the API's JSON (snake_case keys, UTC timestamps), so the
// fakes and the App Group cache read and write them with `WireJSON`. GooseAPI adapts the
// generated client's types to them; nothing outside GooseAPI sees a generated type.

/// A day, named by the local date on which it starts, such as `2026-11-26`.
public struct LocalDate: RawRepresentable, Codable, Hashable, Comparable, Sendable,
	ExpressibleByStringLiteral, CustomStringConvertible
{
	public let rawValue: String

	public init(rawValue: String) { self.rawValue = rawValue }
	public init(stringLiteral value: String) { rawValue = value }

	public init(from decoder: any Decoder) throws {
		rawValue = try decoder.singleValueContainer().decode(String.self)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}

	public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.rawValue < rhs.rawValue }
	public var description: String { rawValue }
}

public enum Pursuer: String, Codable, Hashable, Sendable {
	case goose
}

// MARK: - The chase

public enum ChaseState: String, Codable, Hashable, Sendable {
	case running, complete, short, caught
}

public struct Streak: Codable, Hashable, Sendable {
	public var completeDays: Int
	public var stage: Int

	public init(completeDays: Int, stage: Int) {
		self.completeDays = completeDays
		self.stage = stage
	}
}

/// One habit's progress in a day.
public struct ChaseHabit: Codable, Hashable, Sendable, Identifiable {
	public var habitID: UUID
	public var name: String
	public var unit: String
	public var target: Int
	public var chunk: Int
	public var logged: Int
	public var steps: Double
	public var done: Bool

	public var id: UUID { habitID }

	public init(habitID: UUID, name: String, unit: String, target: Int, chunk: Int, logged: Int, steps: Double, done: Bool) {
		self.habitID = habitID
		self.name = name
		self.unit = unit
		self.target = target
		self.chunk = chunk
		self.logged = logged
		self.steps = steps
		self.done = done
	}

	enum CodingKeys: String, CodingKey {
		case habitID = "habitId", name, unit, target, chunk, logged, steps, done
	}
}

/// The state of a day's chase at `asOf`, as the server worked it out.
public struct Chase: Codable, Hashable, Sendable {
	public var date: LocalDate
	public var pursuer: Pursuer
	public var state: ChaseState
	public var asOf: Date
	public var lead: Double
	public var startingLead: Double
	public var earned: Double
	public var walked: Double
	public var stepsPerHour: Double
	public var dayStartsAt: Date
	public var dayEndsAt: Date
	public var nextDayStartsAt: Date
	public var caughtAt: Date?
	public var habits: [ChaseHabit]
	public var streak: Streak

	public init(
		date: LocalDate, pursuer: Pursuer, state: ChaseState, asOf: Date, lead: Double, startingLead: Double,
		earned: Double, walked: Double, stepsPerHour: Double, dayStartsAt: Date, dayEndsAt: Date,
		nextDayStartsAt: Date, caughtAt: Date?, habits: [ChaseHabit], streak: Streak
	) {
		self.date = date
		self.pursuer = pursuer
		self.state = state
		self.asOf = asOf
		self.lead = lead
		self.startingLead = startingLead
		self.earned = earned
		self.walked = walked
		self.stepsPerHour = stepsPerHour
		self.dayStartsAt = dayStartsAt
		self.dayEndsAt = dayEndsAt
		self.nextDayStartsAt = nextDayStartsAt
		self.caughtAt = caughtAt
		self.habits = habits
		self.streak = streak
	}
}

public enum ChaseEventKind: String, Codable, Hashable, Sendable {
	case gain, complete, caught, undone
}

/// What a log or an undo did.
public struct ChaseEvent: Codable, Hashable, Sendable {
	public var kind: ChaseEventKind
	public var habitID: UUID
	public var steps: Double

	public init(kind: ChaseEventKind, habitID: UUID, steps: Double) {
		self.kind = kind
		self.habitID = habitID
		self.steps = steps
	}

	enum CodingKeys: String, CodingKey {
		case kind, habitID = "habitId", steps
	}
}

/// One day's result in the history.
public struct DaySummary: Codable, Hashable, Sendable {
	public var date: LocalDate
	public var pursuer: Pursuer
	public var result: ChaseState
	public var endLead: Double?
	public var completeDays: Int

	public init(date: LocalDate, pursuer: Pursuer, result: ChaseState, endLead: Double?, completeDays: Int) {
		self.date = date
		self.pursuer = pursuer
		self.result = result
		self.endLead = endLead
		self.completeDays = completeDays
	}
}

// MARK: - Habits and logs

public struct Habit: Codable, Hashable, Sendable, Identifiable {
	public var id: UUID
	public var name: String
	public var unit: String
	public var target: Int
	public var chunk: Int
	public var position: Int
	public var effectiveFrom: LocalDate
	public var archivedFrom: LocalDate?

	public init(id: UUID, name: String, unit: String, target: Int, chunk: Int, position: Int, effectiveFrom: LocalDate, archivedFrom: LocalDate?) {
		self.id = id
		self.name = name
		self.unit = unit
		self.target = target
		self.chunk = chunk
		self.position = position
		self.effectiveFrom = effectiveFrom
		self.archivedFrom = archivedFrom
	}
}

/// A new habit.
public struct HabitDraft: Codable, Hashable, Sendable {
	public var name: String
	public var unit: String
	public var target: Int
	public var chunk: Int

	public init(name: String, unit: String, target: Int, chunk: Int) {
		self.name = name
		self.unit = unit
		self.target = target
		self.chunk = chunk
	}
}

/// The fields of a habit to change; `nil` leaves a field as it is.
public struct HabitChanges: Codable, Hashable, Sendable {
	public var name: String?
	public var unit: String?
	public var target: Int?
	public var chunk: Int?
	public var position: Int?

	public init(name: String? = nil, unit: String? = nil, target: Int? = nil, chunk: Int? = nil, position: Int? = nil) {
		self.name = name
		self.unit = unit
		self.target = target
		self.chunk = chunk
		self.position = position
	}
}

public enum LogSource: String, Codable, Hashable, Sendable {
	case app, widget, shortcuts, api, mcp
}

/// A log as the device sends it. The device creates `id` and `loggedAt` once and sends the same
/// values on every retry (constitution §3). This is also what the retry queue stores.
public struct LogRequest: Codable, Hashable, Sendable, Identifiable {
	public var id: UUID
	public var habitID: UUID
	public var amount: Int?
	public var loggedAt: Date
	public var source: LogSource

	public init(id: UUID, habitID: UUID, amount: Int?, loggedAt: Date, source: LogSource) {
		self.id = id
		self.habitID = habitID
		self.amount = amount
		self.loggedAt = loggedAt
		self.source = source
	}

	enum CodingKeys: String, CodingKey {
		case id, habitID = "habitId", amount, loggedAt, source
	}
}

/// A log as the server holds it.
public struct LogEntry: Codable, Hashable, Sendable, Identifiable {
	public var id: UUID
	public var habitID: UUID
	public var amount: Int
	public var loggedAt: Date
	public var source: LogSource
	public var date: LocalDate
	public var steps: Double
	public var undoneAt: Date?

	public init(id: UUID, habitID: UUID, amount: Int, loggedAt: Date, source: LogSource, date: LocalDate, steps: Double, undoneAt: Date?) {
		self.id = id
		self.habitID = habitID
		self.amount = amount
		self.loggedAt = loggedAt
		self.source = source
		self.date = date
		self.steps = steps
		self.undoneAt = undoneAt
	}

	enum CodingKeys: String, CodingKey {
		case id, habitID = "habitId", amount, loggedAt, source, date, steps, undoneAt
	}
}

/// A log, what it did, and the chase after it.
public struct LogResult: Codable, Hashable, Sendable {
	public var log: LogEntry
	public var event: ChaseEvent
	public var chase: Chase

	public init(log: LogEntry, event: ChaseEvent, chase: Chase) {
		self.log = log
		self.event = event
		self.chase = chase
	}
}

// MARK: - The account

/// Day settings waiting for the day `effectiveFrom`.
public struct PendingDay: Codable, Hashable, Sendable {
	public var effectiveFrom: LocalDate
	public var timeZone: String
	public var dayStart: String
	public var dayEnd: String

	public init(effectiveFrom: LocalDate, timeZone: String, dayStart: String, dayEnd: String) {
		self.effectiveFrom = effectiveFrom
		self.timeZone = timeZone
		self.dayStart = dayStart
		self.dayEnd = dayEnd
	}
}

/// The signed-in user. The day fields are the ones in effect today.
public struct Account: Codable, Hashable, Sendable, Identifiable {
	public var id: UUID
	public var email: String
	public var displayName: String
	public var pursuer: Pursuer
	public var timeZone: String
	public var dayStart: String
	public var dayEnd: String
	public var pending: PendingDay?
	public var createdAt: Date

	public init(id: UUID, email: String, displayName: String, pursuer: Pursuer, timeZone: String, dayStart: String, dayEnd: String, pending: PendingDay?, createdAt: Date) {
		self.id = id
		self.email = email
		self.displayName = displayName
		self.pursuer = pursuer
		self.timeZone = timeZone
		self.dayStart = dayStart
		self.dayEnd = dayEnd
		self.pending = pending
		self.createdAt = createdAt
	}
}

/// The account fields to change; `nil` leaves a field as it is.
public struct AccountChanges: Codable, Hashable, Sendable {
	public var displayName: String?
	public var pursuer: Pursuer?
	public var timeZone: String?
	public var dayStart: String?
	public var dayEnd: String?

	public init(displayName: String? = nil, pursuer: Pursuer? = nil, timeZone: String? = nil, dayStart: String? = nil, dayEnd: String? = nil) {
		self.displayName = displayName
		self.pursuer = pursuer
		self.timeZone = timeZone
		self.dayStart = dayStart
		self.dayEnd = dayEnd
	}
}

/// A new app session. The token is returned this once only.
public struct NewSession: Codable, Hashable, Sendable {
	public var sessionToken: String
	public var expiresAt: Date
	public var user: Account

	public init(sessionToken: String, expiresAt: Date, user: Account) {
		self.sessionToken = sessionToken
		self.expiresAt = expiresAt
		self.user = user
	}
}

/// An app session in the list of sessions.
public struct AppSession: Codable, Hashable, Sendable, Identifiable {
	public var id: UUID
	public var deviceName: String
	public var createdAt: Date
	public var lastUsedAt: Date
	public var current: Bool

	public init(id: UUID, deviceName: String, createdAt: Date, lastUsedAt: Date, current: Bool) {
		self.id = id
		self.deviceName = deviceName
		self.createdAt = createdAt
		self.lastUsedAt = lastUsedAt
		self.current = current
	}
}

public enum KeyKind: String, Codable, Hashable, Sendable {
	case api, mcp
}

/// An API key or an MCP key. The secret is never listed.
public struct Key: Codable, Hashable, Sendable, Identifiable {
	public var id: UUID
	public var kind: KeyKind
	public var name: String
	public var createdAt: Date
	public var lastUsedAt: Date?

	public init(id: UUID, kind: KeyKind, name: String, createdAt: Date, lastUsedAt: Date?) {
		self.id = id
		self.kind = kind
		self.name = name
		self.createdAt = createdAt
		self.lastUsedAt = lastUsedAt
	}
}

/// A new key, with its secret, which is shown this once only.
public struct NewKey: Codable, Hashable, Sendable {
	public var key: Key
	public var secret: String

	public init(key: Key, secret: String) {
		self.key = key
		self.secret = secret
	}

	public init(from decoder: any Decoder) throws {
		key = try Key(from: decoder)
		secret = try decoder.container(keyedBy: SecretKey.self).decode(String.self, forKey: .secret)
	}

	public func encode(to encoder: any Encoder) throws {
		try key.encode(to: encoder)
		var container = encoder.container(keyedBy: SecretKey.self)
		try container.encode(secret, forKey: .secret)
	}

	private enum SecretKey: String, CodingKey { case secret }
}

// MARK: - The profile

public struct ProfileSettings: Codable, Hashable, Sendable {
	public var handle: String?
	public var isPublic: Bool

	public init(handle: String?, isPublic: Bool) {
		self.handle = handle
		self.isPublic = isPublic
	}

	enum CodingKeys: String, CodingKey {
		case handle, isPublic = "public"
	}
}

public struct ProfileDay: Codable, Hashable, Sendable {
	public var date: LocalDate
	public var result: ChaseState

	public init(date: LocalDate, result: ChaseState) {
		self.date = date
		self.result = result
	}
}

/// What anyone can read about a user who published a profile.
public struct PublicProfile: Codable, Hashable, Sendable {
	public var displayName: String
	public var pursuer: Pursuer
	public var completeDays: Int
	public var stage: Int
	public var state: ChaseState
	public var lead: Double
	public var asOf: Date
	public var stepsPerHour: Double
	public var dayEndsAt: Date
	public var days: [ProfileDay]

	public init(displayName: String, pursuer: Pursuer, completeDays: Int, stage: Int, state: ChaseState, lead: Double, asOf: Date, stepsPerHour: Double, dayEndsAt: Date, days: [ProfileDay]) {
		self.displayName = displayName
		self.pursuer = pursuer
		self.completeDays = completeDays
		self.stage = stage
		self.state = state
		self.lead = lead
		self.asOf = asOf
		self.stepsPerHour = stepsPerHour
		self.dayEndsAt = dayEndsAt
		self.days = days
	}
}

// MARK: - Reminders and installations

/// Local times in the user's time zone, such as 22:00 to 07:00.
public struct QuietHours: Codable, Hashable, Sendable {
	public var start: String
	public var end: String

	public init(start: String, end: String) {
		self.start = start
		self.end = end
	}
}

public struct Reminders: Codable, Hashable, Sendable {
	public var enabled: Bool
	public var whenLeadBelow: Int
	public var quietHours: QuietHours?

	public init(enabled: Bool, whenLeadBelow: Int, quietHours: QuietHours?) {
		self.enabled = enabled
		self.whenLeadBelow = whenLeadBelow
		self.quietHours = quietHours
	}
}

public enum PushEnvironment: String, Codable, Hashable, Sendable {
	case sandbox, production
}

/// This installation's push tokens.
public struct DeviceRegistration: Codable, Hashable, Sendable {
	public var apnsToken: String
	public var widgetPushToken: String?
	public var environment: PushEnvironment
	public var appVersion: String

	public init(apnsToken: String, widgetPushToken: String?, environment: PushEnvironment, appVersion: String) {
		self.apnsToken = apnsToken
		self.widgetPushToken = widgetPushToken
		self.environment = environment
		self.appVersion = appVersion
	}
}
