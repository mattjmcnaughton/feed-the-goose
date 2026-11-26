import SwiftUI

/// The scene, drawn with Canvas at any size, in the prototype's 340 x 176 units.
struct SceneCanvas: View {
	let pose: Pose
	var onDraw: ((Double) -> Void)? = nil
	/// Fill the width and crop the sky, as the widget does, instead of keeping the whole scene.
	var cropSky = false

	var body: some View {
		let canvas = Canvas { ctx, size in
			let t0 = CACurrentMediaTime()
			var c = ctx
			if cropSky {
				// Fit the bottom 124 units (ground and goose) to the height, and let the sky and
				// ground run past the scene's 340-unit edges to fill a wider frame.
				let s = min(size.width / SCENE.width, size.height / 124)
				c.clip(to: Path(CGRect(origin: .zero, size: size)))
				c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pose.sky.bg))
				c.translateBy(x: (size.width - SCENE.width * s) / 2, y: size.height - SCENE.height * s)
				c.scaleBy(x: s, y: s)
			} else {
				let s = size.width / SCENE.width
				c.scaleBy(x: s, y: s)
				// Canvas does not clip to its bounds; the SVG viewBox did.
				c.clip(to: Path(CGRect(origin: .zero, size: SCENE)))
			}
			drawScene(c, pose)
			onDraw?(CACurrentMediaTime() - t0)
		}
		if cropSky { canvas } else { canvas.aspectRatio(SCENE.width / SCENE.height, contentMode: .fit) }
	}
}

/// The prototype's `.stage`: scene, ink rule, and the readout below it.
struct StageView: View {
	let pose: Pose
	var onDraw: ((Double) -> Void)? = nil

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			SceneCanvas(pose: pose, onDraw: onDraw)
			Rectangle().fill(INK).frame(height: 3)
			VStack(alignment: .leading, spacing: 4) {
				Text(pose.say.head)
					.font(.custom("Shrikhand-Regular", size: 24))
					.foregroundStyle(pose.say.tone == .good ? Color(hex: 0x17804a) : pose.say.tone == .bad ? Color(hex: 0xd63a1e) : INK)
					.lineSpacing(0)
				Text(pose.say.sub)
					.font(.system(size: 14, design: .rounded))
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
