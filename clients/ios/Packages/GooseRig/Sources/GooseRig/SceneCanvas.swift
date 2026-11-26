import SwiftUI

/// A placeholder for the scene that T12 ports from `spikes/swiftui-goose/`. It fills its frame
/// with the sky and the ground in the prototype's proportions.
public struct SceneCanvas: View {
	/// The prototype's scene, in its own units.
	public static let sceneSize = CGSize(width: 340, height: 176)

	public init() {}

	public var body: some View {
		Canvas { context, size in
			let ground = size.height * 0.78
			context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: ground)), with: .color(.cyan.opacity(0.25)))
			context.fill(Path(CGRect(x: 0, y: ground, width: size.width, height: size.height - ground)), with: .color(.green.opacity(0.35)))
		}
		.clipped()
		.aspectRatio(Self.sceneSize, contentMode: .fit)
	}
}
