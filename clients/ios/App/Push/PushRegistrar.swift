import Foundation
import GooseCore

/// The parts of iOS that push registration needs: notification permission and a device token.
/// `SystemRemoteNotifications` asks iOS; tests pass a fake.
protocol RemoteNotifications: Sendable {
	/// Asks for permission to show alerts and play sounds. False when the user refuses.
	func requestAuthorization() async throws -> Bool
	/// Registers for remote notifications and waits for the token.
	func deviceToken() async throws -> Data
}

/// What turning reminders on did on this phone.
enum PushOutcome: Equatable, Sendable {
	/// The server has this installation's token.
	case registered
	/// The user refused notifications, so no reminder can show.
	case denied
	/// Permission was given, but iOS issued no token, such as a simulator build without a
	/// signing team. The reason is iOS's own message.
	case noToken(String)
}

/// Registers this installation for reminders, and removes the registration on sign-out
/// (TDD §6.9). The installation ID is the one kept in the App Group.
struct PushRegistrar: Sendable {
	let account: any AccountService
	let shared: SharedStore
	let notifications: any RemoteNotifications
	let appVersion: String

	init(environment: AppEnvironment, notifications: any RemoteNotifications, appVersion: String = Self.bundleVersion) {
		account = environment.account
		shared = environment.shared
		self.notifications = notifications
		self.appVersion = appVersion
	}

	/// Debug builds get tokens for APNs' sandbox; release builds for production.
	#if DEBUG
		static let pushEnvironment = PushEnvironment.sandbox
	#else
		static let pushEnvironment = PushEnvironment.production
	#endif

	static var bundleVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
	}

	/// Asks for permission, then for a token, then sends the token to the server. Throws
	/// `APIError` only when the server refuses the token.
	func register() async throws -> PushOutcome {
		do {
			guard try await notifications.requestAuthorization() else { return .denied }
		} catch {
			return .denied
		}
		let token: Data
		do {
			token = try await notifications.deviceToken()
		} catch {
			return .noToken(error.localizedDescription)
		}
		let registration = DeviceRegistration(
			apnsToken: token.map { String(format: "%02x", $0) }.joined(),
			widgetPushToken: nil, environment: Self.pushEnvironment, appVersion: appVersion
		)
		try await account.registerDevice(installationID: shared.installationID(), registration)
		return .registered
	}

	/// Removes this installation's registration, so a signed-out phone gets no reminders. A
	/// phone that never registered gets a 404, which is ignored like any other failure: the
	/// user still signs out.
	func unregister() async {
		try? await account.deleteDevice(installationID: shared.installationID())
	}
}
