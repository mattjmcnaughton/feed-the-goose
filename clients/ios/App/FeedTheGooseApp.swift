import GooseCore
import SwiftUI
import WidgetKit

@main
struct FeedTheGooseApp: App {
	private let environment = LiveEnvironment.make()

	init() {
		#if DEBUG
			// `-FTGSharingProbe <value>` writes the value where the widget can read it. The
			// sharing UI test uses it to prove the App Group and the Keychain are shared.
			if let value = UserDefaults.standard.string(forKey: "FTGSharingProbe"),
			   let probe = SharingProbe(infoDictionary: Bundle.main.infoDictionary) {
				let failures = probe.write(value)
				print("FTGSharingProbe wrote \(value): appGroup=\(failures.appGroup?.description ?? "ok") keychain=\(failures.keychain?.description ?? "ok")")
				WidgetCenter.shared.reloadAllTimelines()
			}
		#endif
	}

	var body: some Scene {
		WindowGroup {
			#if DEBUG
				if ProcessInfo.processInfo.arguments.contains("-FTGRigGallery") {
					RigGalleryView()
				} else {
					RootView(environment: environment)
				}
			#else
				RootView(environment: environment)
			#endif
		}
	}
}
