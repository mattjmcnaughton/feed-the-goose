import SwiftUI

// Just enough SVG path syntax for rig.js: M L H V C Q Z, absolute and relative.
extension Path {
	init(svg d: String) {
		self.init()
		var tokens: [String] = []
		var num = ""
		func flush() { if !num.isEmpty { tokens.append(num); num = "" } }
		for ch in d {
			if ch.isLetter { flush(); tokens.append(String(ch)) }
			else if ch == " " || ch == "," { flush() }
			else if ch == "-" { flush(); num = "-" }
			else { num.append(ch) }
		}
		flush()
		var i = 0
		var cmd = "M"
		var cur = CGPoint.zero
		var start = CGPoint.zero
		func n() -> Double { defer { i += 1 }; return Double(tokens[i])! }
		while i < tokens.count {
			if let c = tokens[i].first, c.isLetter { cmd = tokens[i]; i += 1; if cmd == "Z" || cmd == "z" { closeSubpath(); cur = start; continue } }
			let rel = cmd == cmd.lowercased()
			let o = rel ? cur : .zero
			func pt() -> CGPoint { let x = n(), y = n(); return CGPoint(x: o.x + x, y: o.y + y) }
			switch cmd.uppercased() {
			case "M": cur = pt(); start = cur; move(to: cur); cmd = rel ? "l" : "L"
			case "L": cur = pt(); addLine(to: cur)
			case "H": cur.x = (rel ? cur.x : 0) + n(); addLine(to: cur)
			case "V": cur.y = (rel ? cur.y : 0) + n(); addLine(to: cur)
			case "C": let a = pt(), b = pt(), e = pt(); addCurve(to: e, control1: a, control2: b); cur = e
			case "Q": let a = pt(), e = pt(); addQuadCurve(to: e, control: a); cur = e
			default: fatalError("Unsupported path command \(cmd)")
			}
		}
	}
}
