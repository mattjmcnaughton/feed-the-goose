import SwiftUI

/// The goose's rank, from the streak stage the server sends (0 to 4). Each stage draws a bigger
/// goose; the first is a yellow gosling. From docs/prototypes/src/06-streak-stakes.src.html.
public enum Stage: Int, CaseIterable, Sendable {
	case gosling, goose, bigGoose, bossGoose, giantGoose

	/// The goose's size as a share of the full-grown art.
	var size: Double { [0.5, 0.75, 1, 1.3, 1.7][rawValue] }
	var tint: Color { self == .gosling ? GOSLING : WHITE }

	public var name: String { ["Gosling", "Goose", "Big goose", "Boss goose", "Giant goose"][rawValue] }
}

// The still scene for each state of a chase, for the widgets and for the Today screen between
// clips. Each takes the chase as plain values: `lead` is the share of a day's head start (1 is
// 100 steps), `hour` is the local time of day for the sky (6 to 24), and `stage` sizes the
// goose. Snap starts and ends on `running`, Feast ends on `complete`, and Peck ends on `caught`.
extension Pose {
	init(hour: Double, stage: Stage) {
		self.init()
		sky = skyAt(hour)
		size = stage.size
		tint = stage.tint
	}

	/// A running day: both of you mid-stride, the goose `lead` of a day behind.
	public static func running(lead: Double, hour: Double, stage: Stage) -> Pose {
		var p = Pose(hour: hour, stage: stage)
		p.phase = 0.9
		p.gx = gooseX(lead, size: stage.size)
		return p
	}

	/// A short day: the day ended with the goose still `lead` behind. It is the running scene at
	/// the hour the day ended, as in docs/prototypes 04-app-screens.
	public static func short(lead: Double, hour: Double, stage: Stage) -> Pose {
		running(lead: lead, hour: hour, stage: stage)
	}

	/// A complete day: the goose fed and asleep where it stopped, you cheering. Feast's last frame.
	public static func complete(lead: Double, hour: Double, stage: Stage) -> Pose {
		let z = stage.size
		var p = Pose(hour: hour, stage: stage)
		let m = halt(feastDuration, 0.3, 0.9)
		p.scroll = m.scroll
		p.phase = m.phase
		p.gx = (gooseX(lead, size: z) - 10) + 22
		p.gy = 13
		p.legs = .sit
		p.neck = -4
		p.head = -4 * 0.6 + 14
		p.belly = 1.2
		p.eye = .shut
		p.zs = sleeping(p.gx, z, feastDuration)
		p.ylegs = .stand
		p.yarms = .up
		return p
	}

	/// A caught day: the goose standing over you, knocked down behind it. Peck's last frame.
	public static func caught(hour: Double, stage: Stage) -> Pose {
		var p = Pose(hour: hour, stage: stage)
		let m = halt(peckDuration, 0.55 - 0.05, 0.55 + 0.1)
		p.scroll = m.scroll
		p.phase = m.phase
		p.gx = caughtX(stage.size)
		p.legs = .stand
		p.neck = -8
		p.head = -4
		p.yx = 20
		p.yy = 13
		p.ylegs = .sit
		p.yarms = .up
		return p
	}
}
