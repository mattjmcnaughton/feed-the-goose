import CoreText
import Synchronization
import SwiftUI

// A port of docs/prototypes/src/rig.js by way of spikes/swiftui-goose: the 340 x 176 scene,
// the goose and runner rigs, and drawScene(_:_:), the counterpart of draw(svg, pose). Angles
// are degrees, clockwise.

let DAWN = 6.0
let MIDNIGHT = 24.0
let DAY = 100.0
let YOU_X = 231.0
let GOOSE_Y = 55.0
let SCENE = CGSize(width: 340, height: 176)

extension Color {
	init(hex: UInt32) {
		self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
	}
}

let INK = Color(hex: 0x1d1a2f)
let BREAD = Color(hex: 0xe8ae4c)
let WHITE = Color(hex: 0xfffdf7)
let ORANGE = Color(hex: 0xff8a1f)
/// The gosling's down, from docs/prototypes/src/06-streak-stakes.src.html.
let GOSLING = Color(hex: 0xffe27a)

func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, v)) }
func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
/// Where the goose stands for a lead: 1 is a full day's head start, 0 is its beak on your back.
/// For a full-size goose this is the prototype's G(). The goose's beak tip is 71 units right of
/// its scale origin and its tail 46 units left, so a goose of another size is placed by its beak
/// tip: at lead 0 every goose's beak is where a full-size goose's is. A goose bigger than full
/// size covers less ground per step, so that at lead 1 its tail is still 6 units inside the
/// scene's left edge.
func gooseX(_ lead: Double, size: Double = 1) -> Double {
	let near = 116.0 + 123, far = max(123, 6 + 117 * size)
	let tip = far + (near - far) * (1 - clamp(lead))
	return tip - 52 - 71 * size
}

struct Sky: Equatable, Sendable { var bg: Color; var x: Double; var y: Double; var fill: Color; var stars: Double }
private let skyStops: [(Double, [Double])] = [
	(6, [255, 214, 165]), (11, [143, 211, 255]), (16, [150, 205, 250]),
	(18.5, [255, 160, 110]), (20.5, [84, 68, 158]), (24, [38, 33, 92]),
]
/// The sky at an hour of the day, from dawn (6) to midnight (24). Hours outside are clamped.
func skyAt(_ hour: Double) -> Sky {
	let h = clamp(hour, DAWN, MIDNIGHT)
	let i = max(1, skyStops.firstIndex { $0.0 >= h } ?? 1)
	let (t0, a) = skyStops[i - 1]
	let (t1, b) = skyStops[i]
	let k = clamp((h - t0) / (t1 - t0))
	let day = h < 19
	let p = day ? (h - DAWN) / 13 : (h - 19) / 10
	let c = (0..<3).map { (lerp(a[$0], b[$0], k)).rounded() / 255 }
	return Sky(bg: Color(red: c[0], green: c[1], blue: c[2]), x: 17 + 306 * p, y: 130 - 92 * sin(.pi * p),
	           fill: day ? Color(hex: 0xffd23f) : Color(hex: 0xfff6d6), stars: clamp((h - 18.5) / 2))
}

enum Legs: Sendable { case run, stand, sit }
enum Arms: Sendable { case run, up }
enum Eye: Sendable { case angry, happy, wide, shut }
/// A prop's placement: translate, rotate, scale. `eaten` is only read for the loaf.
struct Place: Equatable, Sendable { var x: Double; var y: Double; var r = 0.0; var s = 1.0; var eaten = 0.0 }
struct Burst: Equatable, Sendable { var text: String; var x: Double; var y: Double; var size = 22.0; var r = 0.0; var s = 1.0; var o = 1.0 }
struct Zs: Equatable, Sendable { var x: Double; var y: Double; var p: Double }

/// Everything the scene draws at one moment. Every field has its resting value, so a clip only
/// sets what it moves (REST in rig.js). Build one with the chase states in `Chase.swift` or
/// with a `Clip`.
public struct Pose: Equatable, Sendable {
	var sky = skyAt(18)
	var shake = 0.0, phase = 0.0, scroll = 0.0
	var gx = 0.0, gy = 0.0, size = 1.0, tint = WHITE, flip = 1.0, tilt = 0.0, squash = 1.0, belly = 1.0
	var neck = 0.0, head = 0.0, beak = 0.0, wing = 0.0, legs = Legs.run, eye = Eye.angry, bulge = -1.0
	var yx = 0.0, yy = 0.0, yrot = 0.0, ylegs = Legs.run, yarms = Arms.run
	var crust: Place? = nil, loaf: Place? = nil, crumbs: [CGPoint] = [], burst: Burst? = nil, zs: Zs? = nil
}

private let NECK: [CGPoint] = [.init(x: 64, y: 54), .init(x: 78, y: 52), .init(x: 92, y: 42), .init(x: 100, y: 24)]
private func neckAt(_ s: Double) -> CGPoint {
	let w = [pow(1 - s, 3), 3 * pow(1 - s, 2) * s, 3 * (1 - s) * s * s, pow(s, 3)]
	return CGPoint(x: zip(w, NECK).map { $0 * $1.x }.reduce(0, +), y: zip(w, NECK).map { $0 * $1.y }.reduce(0, +))
}

/// The point `off` units in front of the goose's head centre, in scene units.
func mouth(gx: Double, gy: Double = 0, size: Double = 1, flip: Double = 1, neck: Double = 0, head: Double = 0, off: Double = 20) -> CGPoint {
	let a = neck * .pi / 180
	let b = (neck + head) * .pi / 180
	let lx = 64 + 36 * cos(a) + 30 * sin(a) + off * cos(b)
	let ly = 54 + 36 * sin(a) - 30 * cos(a) + off * sin(b) + 2
	let fx = flip < 0 ? 120 - lx : lx
	return CGPoint(x: gx + 52 + (fx - 52) * size, y: GOOSE_Y + gy + 91 + (ly - 91) * size)
}

// Paths are parsed once.
private enum P {
	static let neck = Path(svg: "M64,54 C78,52 92,42 100,24")
	static let body = Path(svg: "M6 40 L26 48 C36 42 52 42 62 46 C74 50 78 62 72 70 C66 78 54 78 44 78 C26 78 12 62 6 40 Z")
	static let wing = Path(svg: "M30 54 C38 46 56 46 62 58 C52 66 38 64 30 54 Z")
	static let legA = Path(svg: "M46 74 V90 H56")
	static let legB = Path(svg: "M58 74 V90 H68")
	static let beakU = Path(svg: "M107 16 L123 24 L108 27 Z")
	static let beakL = Path(svg: "M107 26 L120 27.5 L105 33 Z")
	static let headCircle = Path(ellipseIn: CGRect(x: 89, y: 13, width: 22, height: 22))
	static let throat = Path(svg: "M94.5 33.8 L100 24")
	static let brow = Path(svg: "M97 13.5 L107 17")
	static let happy = Path(svg: "M99.5 22.5 q3.5 -4.5 7 0")
	static let shut = Path(svg: "M99.5 20.5 q3.5 4 7 0")
	static let loaf = Path(svg: "M-17 9 V0 C-17 -11 17 -11 17 0 V9 Z")
	static let score = Path(svg: "M-8 -5 l2 5 M-1 -6 l2 5 M6 -5 l2 5")
	static let crust = Path(roundedRect: CGRect(x: -7, y: -4.5, width: 14, height: 9), cornerRadius: 4)
	static let ylegA = Path(svg: "M17 38 V55 H23")
	static let ylegB = Path(svg: "M24 38 V55 H30")
	static let armsRun = Path(svg: "M13 24 L4 30 M27 22 L37 18")
	static let armsUp = Path(svg: "M13 22 L5 9 M27 22 L35 9")
	static let torso = Path(roundedRect: CGRect(x: 12, y: 17, width: 16, height: 23), cornerRadius: 6)
	static let yhead = Path(ellipseIn: CGRect(x: 12.5, y: 1.5, width: 15, height: 15))
	static let reeds = Path(svg: "M176 132 V112 M184 132 V106")
	static let cattailA = Path(roundedRect: CGRect(x: 173.5, y: 103, width: 5, height: 12), cornerRadius: 2.5)
	static let cattailB = Path(roundedRect: CGRect(x: 181.5, y: 97, width: 5, height: 12), cornerRadius: 2.5)
	// Wider than rig.js (-20 to 360) so a wider frame, like a widget's, has ground to its edges.
	// The dash paths start a whole number of dash periods earlier (460 = 10 x 46, 420 = 6 x 70)
	// so the dashes land where the prototype's do.
	static let ground = Path(svg: "M-400 132 H740")
	static let dashA = Path(svg: "M-506 146 H786")
	static let dashB = Path(svg: "M-466 160 H786")
	/// The prototype's five stars, repeated each side so a wide frame's sky has stars too.
	static let stars: Path = {
		var p = Path()
		for dx in [-340.0, 0, 340] {
			for (x, y, r) in [(41.0, 29.0, 1.5), (116, 62, 1.5), (177, 22, 2), (241, 56, 1.5), (306, 27, 1.5)] {
				p.addEllipse(in: CGRect(x: dx + x - r, y: y - r, width: 2 * r, height: 2 * r))
			}
		}
		return p
	}()
}

func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }

// MARK: Text as outlines, so it can take the SVG's `paint-order="stroke"` outline.

/// The app and the widget extension register the font with `UIAppFonts`.
let displayFont = "Shrikhand-Regular"
private let textCache = Mutex<[String: (Path, Double)]>([:])
/// The glyph outlines of `text` at `size`, baseline at y = 0, and the advance width.
func textPath(_ text: String, size: Double) -> (Path, Double) {
	let key = "\(size)|\(text)"
	if let hit = textCache.withLock({ $0[key] }) { return hit }
	let font = CTFontCreateWithName(displayFont as CFString, size, nil)
	let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
	let path = CGMutablePath()
	for run in CTLineGetGlyphRuns(line) as! [CTRun] {
		let n = CTRunGetGlyphCount(run)
		var glyphs = [CGGlyph](repeating: 0, count: n)
		var pos = [CGPoint](repeating: .zero, count: n)
		CTRunGetGlyphs(run, CFRange(), &glyphs)
		CTRunGetPositions(run, CFRange(), &pos)
		for i in 0..<n {
			// Core Text is y-up; the scene is y-down.
			var t = CGAffineTransform(translationX: pos[i].x, y: 0).scaledBy(x: 1, y: -1)
			if let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) { path.addPath(g) }
		}
	}
	let out = (Path(path), CTLineGetTypographicBounds(line, nil, nil, nil))
	textCache.withLock { $0[key] = out }
	return out
}

// MARK: Drawing

private func style(_ w: Double) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }

extension GraphicsContext {
	mutating func rotate(_ deg: Double, _ x: Double, _ y: Double) {
		translateBy(x: x, y: y); rotate(by: .degrees(deg)); translateBy(x: -x, y: -y)
	}
	mutating func place(_ o: Place) {
		translateBy(x: o.x, y: o.y); rotate(by: .degrees(o.r)); scaleBy(x: o.s, y: o.s)
	}
	func inked(_ p: Path, _ fill: Color, width: Double = 3) {
		self.fill(p, with: .color(fill))
		stroke(p, with: .color(INK), style: style(width))
	}
	func line(_ p: Path, _ color: Color = INK, _ width: Double = 3) { stroke(p, with: .color(color), style: style(width)) }
	func nested(_ body: (inout GraphicsContext) -> Void) { var c = self; body(&c) }
}

/// Draws `p` into `ctx`, whose coordinates are already the scene's 340 x 176 units. The sky and
/// the ground run past the scene's edges, so a caller can show more of them than the scene.
func drawScene(_ ctx: GraphicsContext, _ p: Pose) {
	ctx.fill(Path(CGRect(x: -1000, y: -1000, width: 2340, height: 1132)), with: .color(p.sky.bg))
	ctx.nested { c in c.opacity = p.sky.stars; c.fill(P.stars, with: .color(.white)) }
	ctx.fill(circle(p.sky.x, p.sky.y, 14.5), with: .color(p.sky.fill))
	ctx.stroke(circle(p.sky.x, p.sky.y, 14.5), with: .color(INK), lineWidth: 3)

	var w = ctx
	w.translateBy(x: p.shake, y: 0)
	w.fill(Path(CGRect(x: -400, y: 132, width: 1140, height: 60)), with: .color(Color(hex: 0xa9d68c)))
	w.line(P.ground)
	w.stroke(P.dashA, with: .color(INK), style: StrokeStyle(lineWidth: 3, dash: [10, 36], dashPhase: p.scroll.truncatingRemainder(dividingBy: 46)))
	w.stroke(P.dashB, with: .color(INK), style: StrokeStyle(lineWidth: 3, dash: [6, 64], dashPhase: p.scroll.truncatingRemainder(dividingBy: 70)))
	w.nested { c in
		c.translateBy(x: ((80 - p.scroll).truncatingRemainder(dividingBy: 440) + 440).truncatingRemainder(dividingBy: 440) - 230, y: 0)
		c.line(P.reeds)
		c.inked(P.cattailA, Color(hex: 0x8a5a2b))
		c.inked(P.cattailB, Color(hex: 0x8a5a2b))
	}
	drawGoose(w, p)
	if let loaf = p.loaf {
		w.nested { c in
			c.place(loaf)
			let x = -18.5 + 37 * loaf.eaten
			c.nested { c in
				c.clip(to: Path(CGRect(x: x, y: -14, width: 40, height: 28)))
				c.inked(P.loaf, BREAD)
				c.line(P.score, INK, 2)
			}
			if loaf.eaten > 0 && loaf.eaten < 1 {
				var cut = Path()
				cut.move(to: CGPoint(x: x, y: -8.2 * sqrt(clamp(1 - pow(x / 17, 2)))))
				cut.addLine(to: CGPoint(x: x, y: 9))
				c.line(cut)
			}
		}
	}
	if let crust = p.crust { w.nested { c in c.place(crust); c.inked(P.crust, BREAD, width: 2.5) } }
	for pt in p.crumbs.prefix(6) { w.inked(circle(pt.x, pt.y, 2.4), BREAD, width: 1.5) }
	drawYou(w, p)
	if let b = p.burst {
		w.nested { c in
			c.opacity = clamp(b.o)
			c.drawLayer { c in
				c.place(Place(x: b.x, y: b.y, r: b.r, s: b.s))
				let (path, width) = textPath(b.text, size: b.size)
				c.translateBy(x: -width / 2, y: 0)
				c.stroke(path, with: .color(WHITE), style: style(5))
				c.fill(path, with: .color(INK))
			}
		}
	}
	if let zs = p.zs {
		for (i, letter) in ["z", "z", "Z"].enumerated() {
			let k = (zs.p + Double(i) / 3).truncatingRemainder(dividingBy: 1)
			w.nested { c in
				c.opacity = sin(.pi * k)
				c.drawLayer { c in
					c.translateBy(x: zs.x + 7 * Double(i) + 8 * k, y: zs.y - 24 * k)
					let (path, _) = textPath(letter, size: 12 + 4 * Double(i))
					c.stroke(path, with: .color(INK), style: style(2.5))
					c.fill(path, with: .color(Color(hex: 0xfff6d6)))
				}
			}
		}
	}
}

private func drawGoose(_ ctx: GraphicsContext, _ p: Pose) {
	let run = p.legs == .run
	let bob = run ? -2.5 * abs(sin(p.phase)) : 0
	let swing = run ? 26 * sin(p.phase) : 0
	var g = ctx
	g.translateBy(x: p.gx, y: GOOSE_Y + p.gy + bob)
	g.translateBy(x: 52, y: 91); g.scaleBy(x: p.size, y: p.size); g.translateBy(x: -52, y: -91)
	if p.flip < 0 { g.translateBy(x: 120, y: 0); g.scaleBy(x: -1, y: 1) }
	g.rotate(p.tilt, 44, 88)
	g.translateBy(x: 0, y: 91); g.scaleBy(x: 1, y: p.squash); g.translateBy(x: 0, y: -91)

	if p.legs != .sit {
		for (path, a, x) in [(P.legA, swing, 46.0), (P.legB, -swing, 58.0)] {
			g.nested { c in
				c.rotate(a, x, 74)
				c.stroke(path, with: .color(INK), style: style(7.5))
				c.stroke(path, with: .color(ORANGE), style: style(3))
			}
		}
	}
	let swallowing = p.bulge > 0 && p.bulge < 1
	let bulge = neckAt(1 - p.bulge)
	g.nested { c in
		c.rotate(p.neck, 64, 54)
		c.stroke(P.neck, with: .color(INK), style: style(17))
		if swallowing { c.fill(circle(bulge.x, bulge.y, 12), with: .color(INK)) }
	}
	g.nested { c in
		c.translateBy(x: 44, y: 62); c.scaleBy(x: p.belly, y: p.belly); c.translateBy(x: -44, y: -62)
		c.inked(P.body, p.tint)
	}
	g.nested { c in c.rotate(p.wing, 60, 57); c.inked(P.wing, Color(hex: 0xe6e1f0)) }
	g.nested { c in
		c.rotate(p.neck, 64, 54)
		c.stroke(P.neck, with: .color(p.tint), style: style(11))
		if swallowing { c.fill(circle(bulge.x, bulge.y, 10.5), with: .color(p.tint)) }
		c.nested { h in
			h.rotate(p.head, 100, 24)
			h.nested { b in b.rotate(-0.3 * p.beak, 107, 26); b.inked(P.beakU, ORANGE) }
			h.nested { b in b.rotate(0.7 * p.beak, 107, 26); b.inked(P.beakL, ORANGE) }
			h.inked(P.headCircle, p.tint)
		}
		c.stroke(P.throat, with: .color(p.tint), style: style(11))
		c.nested { f in
			f.rotate(p.head, 100, 24)
			switch p.eye {
			case .angry:
				f.fill(circle(103, 21, 2.6), with: .color(INK))
				f.line(P.brow, INK, 2.5)
			case .happy: f.line(P.happy, INK, 2.5)
			case .wide:
				f.fill(circle(103, 20.5, 4.4), with: .color(.white))
				f.line(circle(103, 20.5, 4.4), INK, 2)
				f.fill(circle(103.6, 20.5, 1.7), with: .color(INK))
			case .shut: f.line(P.shut, INK, 2.5)
			}
		}
	}
}

private func drawYou(_ ctx: GraphicsContext, _ p: Pose) {
	let sat = p.ylegs == .sit
	let stride = p.ylegs == .run ? 30 * sin(p.phase + 1) : 0
	let ybob = p.ylegs == .run ? -2 * abs(sin(p.phase + 1)) : 0
	var y = ctx
	y.translateBy(x: YOU_X + p.yx, y: 96 + p.yy + ybob)
	y.scaleBy(x: 0.9, y: 0.9)
	y.rotate(p.yrot, 20, 30)
	y.nested { c in c.rotate(sat ? -78 : stride, 17, 38); c.line(P.ylegA) }
	y.nested { c in c.rotate(sat ? -90 : -stride, 24, 38); c.line(P.ylegB) }
	y.line(p.yarms == .up ? P.armsUp : P.armsRun)
	y.inked(P.torso, Color(hex: 0xff5a3c))
	y.inked(P.yhead, Color(hex: 0xffd23f))
}
