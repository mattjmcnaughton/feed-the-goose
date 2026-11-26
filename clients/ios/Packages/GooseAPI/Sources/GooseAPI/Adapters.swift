internal import Foundation
internal import GooseCore

// Adapters from the generated client's types to GooseCore's models, and back for request
// bodies. A response that breaks the contract, such as an ID that is not a UUID, throws
// `APIError.unexpectedResponse`.

typealias Schemas = Components.Schemas

func uuid(_ string: String) throws -> UUID {
	guard let id = UUID(uuidString: string) else { throw APIError.unexpectedResponse("\(string) is not a UUID") }
	return id
}

extension Chase {
	init(_ chase: Schemas.Chase) throws {
		self.init(
			date: LocalDate(rawValue: chase.date),
			pursuer: Pursuer(chase.pursuer),
			state: ChaseState(chase.state),
			asOf: chase.asOf,
			lead: chase.lead,
			startingLead: chase.startingLead,
			earned: chase.earned,
			walked: chase.walked,
			stepsPerHour: chase.stepsPerHour,
			dayStartsAt: chase.dayStartsAt,
			dayEndsAt: chase.dayEndsAt,
			nextDayStartsAt: chase.nextDayStartsAt,
			caughtAt: chase.caughtAt,
			habits: try chase.habits.map(ChaseHabit.init),
			streak: Streak(completeDays: chase.streak.completeDays, stage: chase.streak.stage)
		)
	}
}

extension ChaseHabit {
	init(_ habit: Schemas.ChaseHabit) throws {
		self.init(
			habitID: try uuid(habit.habitId), name: habit.name, unit: habit.unit, target: habit.target,
			chunk: habit.chunk, logged: habit.logged, steps: habit.steps, done: habit.done
		)
	}
}

extension Pursuer {
	init(_ pursuer: Schemas.Pursuer) {
		switch pursuer {
		case .goose: self = .goose
		}
	}

	var schema: Schemas.Pursuer {
		switch self {
		case .goose: .goose
		}
	}
}

extension ChaseState {
	init(_ state: Schemas.ChaseState) {
		switch state {
		case .running: self = .running
		case .complete: self = .complete
		case .short: self = .short
		case .caught: self = .caught
		}
	}
}

extension ChaseEvent {
	init(_ event: Schemas.Event) throws {
		let kind: ChaseEventKind = switch event.kind {
		case .gain: .gain
		case .complete: .complete
		case .caught: .caught
		case .undone: .undone
		}
		self.init(kind: kind, habitID: try uuid(event.habitId), steps: event.steps)
	}
}

extension DaySummary {
	init(_ day: Schemas.DaySummary) {
		self.init(
			date: LocalDate(rawValue: day.date), pursuer: Pursuer(day.pursuer), result: ChaseState(day.result),
			endLead: day.endLead, completeDays: day.completeDays
		)
	}
}

extension Habit {
	init(_ habit: Schemas.Habit) throws {
		self.init(
			id: try uuid(habit.id), name: habit.name, unit: habit.unit, target: habit.target, chunk: habit.chunk,
			position: habit.position, effectiveFrom: LocalDate(rawValue: habit.effectiveFrom),
			archivedFrom: habit.archivedFrom.map(LocalDate.init(rawValue:))
		)
	}
}

extension LogSource {
	init(_ source: Schemas.Source) {
		switch source {
		case .app: self = .app
		case .widget: self = .widget
		case .shortcuts: self = .shortcuts
		case .api: self = .api
		case .mcp: self = .mcp
		}
	}

	var schema: Schemas.Source {
		switch self {
		case .app: .app
		case .widget: .widget
		case .shortcuts: .shortcuts
		case .api: .api
		case .mcp: .mcp
		}
	}
}

extension LogEntry {
	init(_ log: Schemas.Log) throws {
		self.init(
			id: try uuid(log.id), habitID: try uuid(log.habitId), amount: log.amount, loggedAt: log.loggedAt,
			source: LogSource(log.source), date: LocalDate(rawValue: log.date), steps: log.steps, undoneAt: log.undoneAt
		)
	}
}

extension LogResult {
	init(_ result: Schemas.LogResult) throws {
		self.init(log: try LogEntry(result.log), event: try ChaseEvent(result.event), chase: try Chase(result.chase))
	}
}

extension Account {
	init(_ user: Schemas.User) throws {
		self.init(
			id: try uuid(user.id), email: user.email, displayName: user.displayName, pursuer: Pursuer(user.pursuer),
			timeZone: user.timeZone, dayStart: user.dayStart, dayEnd: user.dayEnd,
			pending: user.pending.map {
				PendingDay(effectiveFrom: LocalDate(rawValue: $0.effectiveFrom), timeZone: $0.timeZone, dayStart: $0.dayStart, dayEnd: $0.dayEnd)
			},
			createdAt: user.createdAt
		)
	}
}

extension NewSession {
	init(_ session: Schemas.SessionCreated) throws {
		self.init(sessionToken: session.sessionToken, expiresAt: session.expiresAt, user: try Account(session.user))
	}
}

extension AppSession {
	init(_ session: Schemas.Session) throws {
		self.init(
			id: try uuid(session.id), deviceName: session.deviceName, createdAt: session.createdAt,
			lastUsedAt: session.lastUsedAt, current: session.current
		)
	}
}

extension KeyKind {
	init(_ kind: Schemas.KeyKind) {
		switch kind {
		case .api: self = .api
		case .mcp: self = .mcp
		}
	}

	var schema: Schemas.KeyKind {
		switch self {
		case .api: .api
		case .mcp: .mcp
		}
	}
}

extension Key {
	init(_ key: Schemas.Key) throws {
		self.init(id: try uuid(key.id), kind: KeyKind(key.kind), name: key.name, createdAt: key.createdAt, lastUsedAt: key.lastUsedAt)
	}
}

extension NewKey {
	init(_ key: Schemas.KeyCreated) throws {
		self.init(
			key: Key(id: try uuid(key.id), kind: KeyKind(key.kind), name: key.name, createdAt: key.createdAt, lastUsedAt: key.lastUsedAt),
			secret: key.secret
		)
	}
}

extension ProfileSettings {
	init(_ settings: Schemas.ProfileSettings) {
		self.init(handle: settings.handle, isPublic: settings._public)
	}
}

extension PublicProfile {
	init(_ profile: Schemas.PublicProfile) {
		self.init(
			displayName: profile.displayName, pursuer: Pursuer(profile.pursuer), completeDays: profile.completeDays,
			stage: profile.stage, state: ChaseState(profile.state), lead: profile.lead, asOf: profile.asOf,
			stepsPerHour: profile.stepsPerHour, dayEndsAt: profile.dayEndsAt,
			days: profile.days.map { ProfileDay(date: LocalDate(rawValue: $0.date), result: ChaseState($0.result)) }
		)
	}
}

extension Reminders {
	init(_ reminders: Schemas.Reminders) {
		self.init(
			enabled: reminders.enabled, whenLeadBelow: reminders.whenLeadBelow,
			quietHours: reminders.quietHours.map { QuietHours(start: $0.start, end: $0.end) }
		)
	}

	var schema: Schemas.Reminders {
		.init(enabled: enabled, quietHours: quietHours.map { .init(end: $0.end, start: $0.start) }, whenLeadBelow: whenLeadBelow)
	}
}
