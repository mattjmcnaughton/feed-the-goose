import Foundation
import Observation

/// The clip a change to the chase deserves. The app draws each one for the user's pursuer.
public enum Clip: String, Codable, Hashable, Sendable {
	/// A log gained steps.
	case snap
	/// The day became complete.
	case feast
	/// The day was caught.
	case peck
}

/// The one place a new chase enters the app, the extension or an intent (TDD §6.5). It caches
/// the chase in the App Group with the device time it arrived, reloads the widgets, and decides
/// which clip, if any, the change deserves.
@MainActor @Observable
public final class ChaseStore {
	/// The last chase received, here or by another process. Nil until one arrives.
	public private(set) var snapshot: ChaseSnapshot?
	/// True when the server said the user has no habit for the current day.
	public private(set) var hasNoChase = false
	/// Why the last fetch failed, until one succeeds.
	public private(set) var lastError: APIError?

	private let service: any ChaseService
	private let shared: SharedStore
	private let now: @Sendable () -> Date
	private let reloadWidgets: @Sendable () -> Void

	/// Nonisolated so that the composition root can build it from any context.
	nonisolated public init(
		service: any ChaseService,
		shared: SharedStore,
		now: @escaping @Sendable () -> Date = Date.init,
		reloadWidgets: @escaping @Sendable () -> Void = {}
	) {
		self.service = service
		self.shared = shared
		self.now = now
		self.reloadWidgets = reloadWidgets
		// The macro's backing storage: a nonisolated init may set stored properties only.
		_snapshot = shared.chaseSnapshot
	}

	/// Picks up a chase that another process wrote to the App Group.
	public func reload() {
		snapshot = shared.chaseSnapshot
	}

	/// Takes the result of the user's own log or undo, and returns the clip for its event. It
	/// does not record Feast or Peck as played: the process that shows a clip calls `markPlayed`.
	@discardableResult
	public func receive(_ result: LogResult) -> Clip? {
		store(result.chase)
		switch result.event.kind {
		case .gain: return .snap
		case .complete: return unplayed(.feast, on: result.chase.date) ?? .snap
		case .caught: return unplayed(.peck, on: result.chase.date)
		case .undone: return nil
		}
	}

	/// Fetches the current chase. A day that went from running to complete chooses Feast, and
	/// from running to caught chooses Peck, compared with the chase this process last held, so a
	/// day finished from a widget still plays in the app. A failed fetch keeps the newest chase,
	/// marked out of date.
	@discardableResult
	public func refresh() async -> Clip? {
		let previous = snapshot
		do {
			let chase = try await service.today()
			guard store(chase) else { return nil }
			guard let previous, previous.chase.date == chase.date, previous.chase.state == .running else { return nil }
			switch chase.state {
			case .complete: return unplayed(.feast, on: chase.date)
			case .caught: return unplayed(.peck, on: chase.date)
			case .running, .short: return nil
			}
		} catch APIError.noChase {
			hasNoChase = true
			lastError = nil
			snapshot = nil
			shared.setChaseSnapshot(nil)
			reloadWidgets()
			return nil
		} catch {
			lastError = error as? APIError ?? .transport(String(describing: error))
			// Read again: a log may have stored a newer chase while the fetch was in flight.
			if var stale = shared.chaseSnapshot ?? snapshot {
				stale.isOutOfDate = true
				snapshot = stale
				shared.setChaseSnapshot(stale)
			}
			return nil
		}
	}

	/// Records that Feast or Peck was shown, so it plays once per day per device.
	public func markPlayed(_ clip: Clip, on date: LocalDate) {
		shared.setPlayed(clip, on: date)
	}

	/// Stores a chase unless a newer one of the same day is already held, here or in another
	/// process, such as the result of a log that landed while a fetch was in flight.
	@discardableResult
	private func store(_ chase: Chase) -> Bool {
		if let current = shared.chaseSnapshot ?? snapshot, current.chase.date == chase.date, current.chase.asOf > chase.asOf {
			snapshot = current
			return false
		}
		let fresh = ChaseSnapshot(chase: chase, receivedAt: now())
		snapshot = fresh
		hasNoChase = false
		lastError = nil
		shared.setChaseSnapshot(fresh)
		reloadWidgets()
		return true
	}

	private func unplayed(_ clip: Clip, on date: LocalDate) -> Clip? {
		shared.played(clip) == date ? nil : clip
	}
}
