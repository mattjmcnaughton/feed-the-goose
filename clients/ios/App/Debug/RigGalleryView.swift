#if DEBUG
	import GooseRig
	import SwiftUI

	/// Shown instead of the root with the `-FTGRigGallery` launch argument. T12 replaces it with
	/// a gallery of the rig's poses and clips.
	struct RigGalleryView: View {
		var body: some View {
			VStack(spacing: 16) {
				Text("Rig gallery").font(.title.bold())
				SceneCanvas()
				Text("Built in T12.").foregroundStyle(.secondary)
			}
			.padding()
		}
	}
#endif
