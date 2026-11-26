import Foundation
import UIKit
import UserNotifications

/// Notification permission from `UNUserNotificationCenter`, and the device token through the
/// app delegate, which is where iOS delivers it.
struct SystemRemoteNotifications: RemoteNotifications {
	func requestAuthorization() async throws -> Bool {
		try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
	}

	func deviceToken() async throws -> Data {
		try await PushAppDelegate.nextToken()
	}
}

struct PushTokenTimeout: LocalizedError {
	var errorDescription: String? { "iOS did not answer the request for a push token within 10 seconds." }
}

/// Receives the device token. `FeedTheGooseApp` installs it with `@UIApplicationDelegateAdaptor`.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate {
	private static var waiting: [UUID: CheckedContinuation<Data, any Error>] = [:]

	/// Registers for remote notifications and waits for iOS to answer, for at most 10 seconds.
	static func nextToken() async throws -> Data {
		let id = UUID()
		return try await withCheckedThrowingContinuation { continuation in
			waiting[id] = continuation
			UIApplication.shared.registerForRemoteNotifications()
			Task {
				try? await Task.sleep(for: .seconds(10))
				waiting.removeValue(forKey: id)?.resume(throwing: PushTokenTimeout())
			}
		}
	}

	private static func answer(_ result: Result<Data, any Error>) {
		let continuations = waiting.values
		waiting.removeAll()
		for continuation in continuations { continuation.resume(with: result) }
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		Self.answer(.success(deviceToken))
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
		Self.answer(.failure(error))
	}
}
