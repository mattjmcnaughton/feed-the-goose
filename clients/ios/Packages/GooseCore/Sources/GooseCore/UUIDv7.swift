import Foundation

extension UUID {
	/// A UUIDv7 (RFC 9562): 48 bits of Unix milliseconds, then random bits, so IDs sort by the
	/// time they were made. The client creates each log's ID this way.
	public static func v7(at date: Date = Date()) -> UUID {
		var bytes = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }
		let milliseconds = UInt64(max(0, date.timeIntervalSince1970 * 1000))
		for index in 0 ..< 6 {
			bytes[index] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - index)))
		}
		bytes[6] = (bytes[6] & 0x0F) | 0x70
		bytes[8] = (bytes[8] & 0x3F) | 0x80
		return UUID(uuid: (
			bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
			bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
		))
	}
}
