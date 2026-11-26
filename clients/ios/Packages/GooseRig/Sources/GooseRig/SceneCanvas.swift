import SwiftUI

/// The scene drawn with one `Canvas`, filling whatever frame it is given.
///
/// The layout is width-flexible: the scene's 340 x 176 units are scaled to fit the frame and
/// sit on its bottom edge, centred, and the sky and the ground extend past the scene's edges to
/// fill the rest. A frame wider than the scene gets more ground and sky at the sides; a taller
/// one gets more sky above. Nothing is letterboxed and nothing in the scene is cropped. Give it
/// `.aspectRatio(SceneCanvas.sceneSize, contentMode: .fit)` to show the prototype's frame.
public struct SceneCanvas: View {
	/// The prototype's scene, in its own units.
	public static let sceneSize = SCENE

	let pose: Pose

	public init(pose: Pose) {
		self.pose = pose
	}

	public var body: some View {
		Canvas { ctx, size in
			var c = ctx
			// Canvas does not clip to its bounds the way the SVG viewBox did.
			c.clip(to: Path(CGRect(origin: .zero, size: size)))
			let s = min(size.width / SCENE.width, size.height / SCENE.height)
			c.translateBy(x: (size.width - SCENE.width * s) / 2, y: size.height - SCENE.height * s)
			c.scaleBy(x: s, y: s)
			drawScene(c, pose)
		}
		.accessibilityHidden(true)
	}
}

/// Plays a clip from `start`, driven by `TimelineView(.animation)`, and holds its last frame
/// once it ends. With Reduce Motion on it shows the last frame straight away.
public struct ClipPlayer<Content: View>: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let clip: Clip
	let start: Date
	let content: (Pose, Double) -> Content

	/// `content` gets each frame's pose and the clip's time in seconds.
	public init(clip: Clip, start: Date, @ViewBuilder content: @escaping (Pose, Double) -> Content) {
		self.clip = clip
		self.start = start
		self.content = content
	}

	public var body: some View {
		if reduceMotion {
			content(clip.pose(at: clip.duration), clip.duration)
		} else {
			TimelineView(.animation(paused: false)) { timeline in
				let t = min(timeline.date.timeIntervalSince(start), clip.duration)
				content(clip.pose(at: t), t)
			}
		}
	}
}

extension ClipPlayer where Content == SceneCanvas {
	public init(clip: Clip, start: Date) {
		self.init(clip: clip, start: start) { pose, _ in SceneCanvas(pose: pose) }
	}
}

/// The prototype's `.stage`: the scene, an ink rule and a readout, 340 points wide. The
/// gallery and the contact sheets use it to compare frames with docs/prototypes.
public struct StageCard: View {
	let pose: Pose
	let caption: Caption

	public init(pose: Pose, caption: Caption) {
		self.pose = pose
		self.caption = caption
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			SceneCanvas(pose: pose).aspectRatio(SCENE, contentMode: .fit)
			Rectangle().fill(INK).frame(height: 3)
			VStack(alignment: .leading, spacing: 4) {
				Text(caption.head)
					.font(.custom(displayFont, size: 24))
					// The prototype's line-height 1.1. SwiftUI's default line for Shrikhand is
					// taller, which pushed the readout down.
					.lineHeight(.exact(points: 26.4))
					.foregroundStyle(caption.tone == .good ? Color(hex: 0x17804a) : caption.tone == .bad ? Color(hex: 0xd63a1e) : INK)
				Text(caption.sub)
					.font(.system(size: 14, design: .rounded))
					.lineHeight(.exact(points: 17.5))
					.foregroundStyle(INK)
			}
			.padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
			.frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
		}
		.frame(width: 340)
		.background(Color(hex: 0xfffaf0))
		.clipShape(RoundedRectangle(cornerRadius: 22))
		.overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.12), lineWidth: 1))
	}
}
