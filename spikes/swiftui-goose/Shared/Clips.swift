import SwiftUI

// A port of the keyframe helpers and three clips (Snap, Feast, Peck) from
// docs/prototypes/src/05-animations.src.html. A clip is a function from seconds to a Pose.

enum E {
	static func io(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
	static func out(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
	static func `in`(_ p: Double) -> Double { pow(p, 2.2) }
}
/// Keyframes: [(time, value)], eased between neighbours and held outside them.
func k(_ t: Double, _ pts: [(Double, Double)], _ e: (Double) -> Double = E.io) -> Double {
	if t <= pts[0].0 { return pts[0].1 }
	for i in 1..<pts.count where t <= pts[i].0 {
		return lerp(pts[i - 1].1, pts[i].1, e((t - pts[i - 1].0) / (pts[i].0 - pts[i - 1].0)))
	}
	return pts[pts.count - 1].1
}
func seg(_ t: Double, _ a: Double, _ b: Double, _ e: (Double) -> Double = E.io) -> Double { e(clamp((t - a) / (b - a))) }
func pulse(_ t: Double, _ a: Double, _ b: Double) -> Double { sin(.pi * clamp((t - a) / (b - a))) }
func pop(_ t: Double, _ t0: Double) -> Double { k(t, [(t0, 0.4), (t0 + 0.12, 1.15), (t0 + 0.22, 1)], E.out) }
func arc(_ t: Double, _ t0: Double, _ t1: Double, _ from: CGPoint, _ to: CGPoint, _ h: Double, spin: Double = 540) -> Place {
	let p = clamp((t - t0) / (t1 - t0))
	return Place(x: lerp(from.x, to.x, p), y: lerp(from.y, to.y, p) - h * 4 * p * (1 - p), r: spin * p)
}
func spray(_ t: Double, _ t0: Double, _ o: CGPoint, _ n: Int = 4, spread: Double = 44, up: Double = 60) -> [CGPoint] {
	let age = t - t0
	if age < 0 || age > 0.5 { return [] }
	return (0..<n).map { i in
		CGPoint(x: o.x + (Double(i) - Double(n - 1) / 2) * spread * age,
		        y: o.y - (up + 22 * Double((i * 7) % 3)) * age + 300 * age * age)
	}
}
/// The ground scrolls at V while you run. halt() slows you to `to` of full speed between a and b.
let V = 64.0
func halt(_ t: Double, _ a: Double, _ b: Double, to: Double = 0) -> (scroll: Double, phase: Double) {
	let p = clamp((t - a) / (b - a))
	let scroll = V * (min(t, a) + (b - a) * (p - ((1 - to) * p * p) / 2) + to * max(0, t - b))
	return (scroll, 14 * scroll / V)
}
let HAND = CGPoint(x: YOU_X + 5, y: 114)
func steps(_ lead: Double) -> Int { Int((lead * DAY).rounded()) }

// A crust: 10 of 50 pushups, one of three habits, at 6 pm with the goose 45 steps back.
let L0 = 0.45
let L1 = L0 + (1.0 / 3) * (10.0 / 50)
let g0 = G(L0)
let g1 = G(L1)
func eatSay(_ done: Bool) -> Say {
	done ? Say(head: "The goose is \(steps(L1)) steps back", sub: "Pushups 30 of 50. That crust bought you \(steps(L1) - steps(L0)) steps.")
		: Say(head: "The goose is \(steps(L0)) steps back", sub: "Pushups 20 of 50. Tossing a crust for 10 more.")
}
func paidSay(_ done: Bool, _ sub: String) -> Say {
	done ? Say(head: "The goose is fed", sub: sub, tone: .good)
		: Say(head: "The goose is \(steps(L0)) steps back", sub: "Reading 15 of 20. Tossing the loaf for the last 5 pages.")
}
// Caught: nearly midnight with the goose 6 steps back.
let C0 = 0.06
let gc = G(C0)
let NIGHT = skyAt(MIDNIGHT)
func caughtSay(_ done: Bool) -> Say {
	done ? Say(head: "The goose got you", sub: "Today is locked. A new chase starts at dawn.", tone: .bad)
		: Say(head: "The goose is \(steps(C0)) steps back", sub: "Pushups 20 of 50, and it is almost midnight.")
}

struct Clip: Identifiable {
	let id: String
	let name: String
	let dur: Double
	let poster: Double
	let frame: (Double) -> Pose
}

let SNAP = Clip(id: "snap", name: "Snap", dur: 1.3, poster: 0.36) { t in
	let hit = 0.42
	let at = mouth(gx: g0, neck: -14, head: -18)
	var p = Pose()
	p.phase = t * 14
	p.scroll = t * V
	p.gx = k(t, [(hit, g0), (0.85, g0 - 30), (1.3, g1)])
	p.neck = k(t, [(0.15, 0), (0.38, -14), (0.5, 8), (0.72, 0)])
	p.head = k(t, [(0.15, 0), (0.38, -18), (0.5, 10), (0.75, 0)])
	p.beak = k(t, [(0.18, 0), (0.34, 44), (hit - 0.02, 44), (hit + 0.03, 0)])
	p.squash = k(t, [(hit, 1), (0.5, 0.92), (0.62, 1.05), (0.76, 1)])
	p.bulge = (t - 0.5) / 0.4
	p.eye = t >= hit && t < 1.05 ? .happy : .angry
	p.yarms = t < 0.14 ? .up : .run
	p.crust = t < hit ? arc(t, 0.06, hit, HAND, at, 30) : nil
	p.crumbs = spray(t, hit, at, 3)
	p.say = eatSay(t >= hit)
	return p
}

let FEAST = Clip(id: "feast", name: "Feast", dur: 3.6, poster: 1.6) { t in
	let m = halt(t, 0.3, 0.9)
	let land = 0.45
	let lx = g0 + 128 - max(0, m.scroll - halt(land, 0.3, 0.9).scroll)
	let bites = [1.2, 1.55, 1.9]
	let n = bites.filter { t >= $0 }.count
	let gx = k(t, [(land, g0), (0.9, g0 - 10)]) + k(t, [(1.2, 0), (1.4, 11), (1.55, 11), (1.75, 22)])
	let neck = k(t, [(0.5, 0), (0.62, -12), (0.95, -12), (1.2, 52), (1.34, 26), (1.55, 52), (1.69, 26), (1.9, 52), (2.15, 0), (2.6, 0), (3, -4)])
	let sit = seg(t, 2.5, 2.8, E.in)
	var p = Pose()
	p.scroll = m.scroll
	p.phase = m.phase
	p.gx = gx
	p.gy = -7 * pulse(t, 0.5, 0.72) + 13 * sit
	p.legs = t < 0.55 ? .run : sit > 0.6 ? .sit : .stand
	p.neck = neck
	p.head = (neck > 0 ? neck * 0.42 : neck * 0.6) + 14 * seg(t, 2.8, 3.1)
	p.beak = k(t, [(1.05, 0), (1.14, 40), (1.2, 0), (1.4, 40), (1.55, 0), (1.75, 40), (1.9, 0)])
	p.belly = k(t, [(1.2, 1), (1.3, 1.07), (1.55, 1.07), (1.65, 1.14), (1.9, 1.14), (2, 1.2)])
	p.squash = k(t, [(2.78, 1), (2.86, 0.9), (3, 1)])
	p.bulge = (t - 2.12) / 0.3
	p.eye = t < 0.5 ? .angry : t < 1.05 ? .wide : t < 2.9 ? .happy : .shut
	p.loaf = t < land ? arc(t, 0.06, land, HAND, CGPoint(x: g0 + 128, y: 137), 42, spin: 360)
		: n < 3 ? Place(x: lx, y: 137, eaten: Double(n) / 3) : nil
	p.crumbs = n > 0 ? spray(t, bites[n - 1], CGPoint(x: gx + 115, y: 140), 4) : []
	p.zs = t >= 3 ? Zs(x: gx + 112, y: GOOSE_Y + 26, p: (t - 3) / 1.4) : nil
	p.ylegs = t < 0.9 ? .run : .stand
	p.yarms = t < 0.14 || t >= 2 ? .up : .run
	p.yy = -10 * (pulse(t, 2, 2.3) + pulse(t, 2.4, 2.7))
	p.say = paidSay(t >= 1.9, "Asleep until dawn. Tomorrow it starts 100 steps back.")
	return p
}

let PECK = Clip(id: "peck", name: "Peck", dur: 2.4, poster: 0.72) { t in
	let hit = 0.55
	let dt = t - hit
	let m = halt(t, hit - 0.05, hit + 0.1)
	var p = Pose()
	p.sky = NIGHT
	p.scroll = m.scroll
	p.phase = m.phase
	p.gx = k(t, [(0, gc), (0.5, 119)], E.in)
	p.legs = t < hit ? .run : .stand
	p.neck = k(t, [(0.2, 0), (0.44, -14), (hit, 30), (0.85, 30), (1.1, -8)])
	p.head = k(t, [(0.2, 0), (0.44, -10), (hit, 24), (0.85, 24), (1.1, -4)])
	p.beak = k(t, [(0.3, 0), (0.44, 34), (hit, 0)]) + 36 * (pulse(t, 1.2, 1.5) + pulse(t, 1.65, 1.95))
	p.wing = -48 * (pulse(t, 1.15, 1.4) + pulse(t, 1.4, 1.65) + pulse(t, 1.65, 1.9))
	p.shake = dt >= 0 ? 5 * sin(dt * 55) * exp(-dt * 7) : 0
	p.burst = dt >= 0 && t < 2 ? Burst(text: "HONK!", x: 168, y: 54, size: 28, r: -7, s: pop(t, hit), o: 1 - seg(t, 1.7, 2)) : nil
	p.yx = k(t, [(hit, 0), (1.05, 20)], E.out)
	p.yy = -30 * pulse(t, hit, 1.05) + 13 * seg(t, hit, 1.05, E.in) - 4 * pulse(t, 1.05, 1.25)
	p.yrot = k(t, [(hit, 0), (0.8, 30), (1.05, 0)])
	p.ylegs = t < hit ? .run : t < 0.95 ? .stand : .sit
	p.yarms = t >= hit ? .up : .run
	p.say = caughtSay(t >= hit)
	return p
}

let CLIPS = [SNAP, FEAST, PECK]
