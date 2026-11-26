import Foundation

/// The only chase arithmetic on the phone (constitution §1, TDD §6.5). It keeps the device time
/// at which a chase was received next to it, so a wrong device clock cannot distort the lead:
/// time is measured on the device from receipt, never by comparing the device clock with the
/// server's `asOf`.
public struct ChaseClock: Hashable, Sendable {
	public let chase: Chase
	/// The device time at which the chase arrived.
	public let receivedAt: Date

	public init(chase: Chase, receivedAt: Date) {
		self.chase = chase
		self.receivedAt = receivedAt
	}

	/// The lead to show at the device time `now`. While the day is running it is
	/// `lead − stepsPerHour × hours since receipt`, stopped at `dayEndsAt` and never below 0.
	/// Otherwise it is the server's lead.
	public func lead(at now: Date) -> Double {
		guard chase.state == .running else { return chase.lead }
		let end = deviceTime(of: chase.dayEndsAt)
		let elapsed = max(0, min(now, end).timeIntervalSince(receivedAt))
		return max(0, chase.lead - chase.stepsPerHour * elapsed / 3600)
	}

	/// The device time at which the server's clock reads `serverTime`, such as `dayEndsAt` or
	/// `nextDayStartsAt`, for scheduling a refresh.
	public func deviceTime(of serverTime: Date) -> Date {
		receivedAt.addingTimeInterval(serverTime.timeIntervalSince(chase.asOf))
	}
}
