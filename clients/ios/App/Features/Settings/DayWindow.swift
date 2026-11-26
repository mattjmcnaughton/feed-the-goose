import Foundation

/// A day's local hours as the API writes them, `"HH:MM"`, and the server's length rule
/// mirrored so the form refuses what the server would (API spec, "Each user's day").
enum DayWindow {
	static let minHours = 8.0
	static let maxHours = 22.0

	/// Minutes after midnight, or nil for a string that is not `HH:MM`.
	static func minutes(_ time: String) -> Int? {
		let parts = time.split(separator: ":")
		guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
		      (0 ..< 24).contains(hour), (0 ..< 60).contains(minute) else { return nil }
		return hour * 60 + minute
	}

	static func time(minutes: Int) -> String {
		String(format: "%02d:%02d", minutes / 60, minutes % 60)
	}

	/// The day's length. An end at or before the start is the next morning, as on the server,
	/// so 06:00 to 00:00 is 18 hours and 06:00 to 06:00 is 24.
	static func hours(start: String, end: String) -> Double? {
		guard let start = minutes(start), let end = minutes(end) else { return nil }
		let length = end > start ? end - start : end + 24 * 60 - start
		return Double(length) / 60
	}

	/// Why the server would refuse these hours, or nil when it would accept them.
	static func problem(start: String, end: String) -> String? {
		guard let hours = hours(start: start, end: end) else { return "Choose a start and an end." }
		guard (minHours ... maxHours).contains(hours) else {
			return "The day must be 8 to 22 hours long. This one is \(describe(hours))."
		}
		return nil
	}

	/// "18 hours", "7 hours 30 minutes".
	static func describe(_ hours: Double) -> String {
		let total = Int((hours * 60).rounded())
		let hourText = total / 60 == 1 ? "1 hour" : "\(total / 60) hours"
		return total % 60 == 0 ? hourText : "\(hourText) \(total % 60) minutes"
	}

	/// Every half hour, for the pickers, plus `including` when it falls between them.
	static func options(including: String...) -> [String] {
		var all = Set(stride(from: 0, to: 24 * 60, by: 30).map { time(minutes: $0) })
		all.formUnion(including.filter { minutes($0) != nil })
		return all.sorted()
	}

	/// The time as the phone's locale writes it, such as "1:00 AM".
	static func label(_ time: String) -> String {
		guard let minutes = minutes(time) else { return time }
		let date = Date(timeIntervalSince1970: TimeInterval(minutes * 60))
		return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))
	}
}
