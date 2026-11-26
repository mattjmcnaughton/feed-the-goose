import Foundation
import SwiftUI
import Testing
@testable import GooseRig

/// The run cycle and the bread in your hand are the only things a clip's first frame adds to the
/// still it starts from: you are mid-throw and the ground is moving.
private func withoutMotion(_ pose: Pose) -> Pose {
	var p = pose
	p.phase = 0
	p.scroll = 0
	p.yarms = .run
	p.crust = nil
	p.loaf = nil
	return p
}

struct ClipTests {
	static let leads = [0.06, 0.45, 0.8]
	static let hours = [7.0, 18, 24]

	@Test(arguments: Stage.allCases)
	func eachClipReturnsTheSamePoseForTheSameTime(stage: Stage) {
		let make: [() -> Clip] = [
			{ .snap(from: 0.45, to: 0.52, hour: 18, stage: stage) },
			{ .feast(lead: 0.45, hour: 18, stage: stage) },
			{ .peck(lead: 0.06, hour: 24, stage: stage) },
		]
		for build in make {
			let a = build(), b = build()
			for i in 0...240 {
				let t = a.duration * Double(i) / 240
				#expect(a.pose(at: t) == a.pose(at: t), "\(a.id) at \(t)")
				#expect(a.pose(at: t) == b.pose(at: t), "\(a.id) at \(t)")
			}
		}
	}

	@Test func clipsHoldTheirEnds() {
		for clip in Clip.examples {
			#expect(clip.pose(at: -1) == clip.pose(at: 0), "\(clip.id)")
			#expect(clip.pose(at: clip.duration + 5) == clip.pose(at: clip.duration), "\(clip.id)")
		}
	}

	@Test(arguments: Stage.allCases)
	func feastEndsOnTheCompleteStill(stage: Stage) {
		for lead in Self.leads {
			for hour in Self.hours {
				let clip = Clip.feast(lead: lead, hour: hour, stage: stage)
				#expect(clip.pose(at: clip.duration) == .complete(lead: lead, hour: hour, stage: stage))
			}
		}
	}

	@Test(arguments: Stage.allCases)
	func peckEndsOnTheCaughtStill(stage: Stage) {
		for lead in Self.leads {
			for hour in Self.hours {
				let clip = Clip.peck(lead: lead, hour: hour, stage: stage)
				#expect(clip.pose(at: clip.duration) == .caught(hour: hour, stage: stage))
			}
		}
	}

	@Test(arguments: Stage.allCases)
	func eachClipStartsOnTheRunningStill(stage: Stage) {
		for lead in Self.leads {
			let running = withoutMotion(.running(lead: lead, hour: 18, stage: stage))
			#expect(withoutMotion(Clip.snap(from: lead, to: lead + 0.1, hour: 18, stage: stage).pose(at: 0)) == running)
			#expect(withoutMotion(Clip.feast(lead: lead, hour: 18, stage: stage).pose(at: 0)) == running)
			#expect(withoutMotion(Clip.peck(lead: lead, hour: 18, stage: stage).pose(at: 0)) == running)
		}
	}

	@Test(arguments: Stage.allCases)
	func snapEndsOnTheRunningStillAtTheNewLead(stage: Stage) {
		let clip = Clip.snap(from: 0.45, to: 0.52, hour: 18, stage: stage)
		#expect(withoutMotion(clip.pose(at: clip.duration)) == withoutMotion(.running(lead: 0.52, hour: 18, stage: stage)))
	}

	/// The spike dropped the crumbs from Feast's seventh contact-sheet frame. That frame is at
	/// 3.6 x 6 / 9 s, which is a hair past 2.40 s, where the third bite's spray ends.
	@Test func feastHasCrumbsOnItsSeventhContactSheetFrame() {
		let clip = Clip.feastExample
		#expect(clip.pose(at: clip.duration * 6 / 9).crumbs.count == 4)
		#expect(clip.pose(at: 2.45).crumbs.isEmpty)
	}
}

struct StageTests {
	@Test func sizesAndTintFollowThePrototype() {
		#expect(Stage.allCases.map(\.size) == [0.5, 0.75, 1, 1.3, 1.7])
		#expect(Stage.gosling.tint == Color(hex: 0xffe27a))
		#expect(Stage.allCases.dropFirst().allSatisfy { $0.tint == Color(hex: 0xfffdf7) })
	}

	/// The goose's beak tip is x 123 in the art and its tail x 6, from its scale origin at x 52.
	private func tip(_ lead: Double, _ stage: Stage) -> Double {
		mouth(gx: gooseX(lead, size: stage.size), size: stage.size, off: 23).x
	}
	private func tail(_ lead: Double, _ stage: Stage) -> Double {
		gooseX(lead, size: stage.size) + 52 - 46 * stage.size
	}

	/// Up to full size the prototype's G(): a full lead is 116 units, with the beak tip at 239
	/// for lead 0 and at 123 for lead 1.
	@Test(arguments: [0.0, 0.3, 1.0])
	func smallerGeeseKeepThePrototypesSpacing(lead: Double) {
		for stage in [Stage.gosling, .goose, .bigGoose] {
			#expect(abs(tip(lead, stage) - (239 - 116 * lead)) < 1e-9, "\(stage)")
		}
	}

	/// At lead 0 every goose's beak is on your back; at lead 1 even the giant's tail is in the
	/// scene, and a bigger lead always puts the goose further back.
	@Test(arguments: Stage.allCases)
	func everyGooseFitsTheScene(stage: Stage) {
		#expect(abs(tip(0, stage) - 239) < 1e-9)
		#expect(tail(1, stage) >= 6 - 1e-9)
		#expect(tip(0.5, stage) < tip(0.4, stage))
	}

	@Test func skyRunsFromDawnToMidnight() {
		#expect(skyAt(6).stars == 0)
		#expect(skyAt(24).stars == 1)
		#expect(skyAt(3) == skyAt(6))
		#expect(skyAt(30) == skyAt(24))
	}
}
