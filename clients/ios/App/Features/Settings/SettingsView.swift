import GooseCore
import SwiftUI

/// Settings (TDD §6.9, PRD S12 to S16): the day and its time zone, reminders, the public
/// profile, habits, keys, sessions, signing out and deleting the account.
struct SettingsView: View {
	@State private var model: SettingsModel
	private let keys: KeysModel
	@Environment(SessionModel.self) private var session
	@State private var editingDay = false
	@State private var confirmingSignOut = false
	@State private var confirmingDelete = false

	init(environment: AppEnvironment) {
		let server = Self.server
		self.init(
			model: SettingsModel(environment: environment, server: server, notifications: SystemRemoteNotifications()),
			keys: KeysModel(environment: environment, server: server)
		)
	}

	init(model: SettingsModel, keys: KeysModel) {
		_model = State(initialValue: model)
		self.keys = keys
	}

	/// The server's address, read the way the composition root reads it.
	static var server: URL {
		let configured = UserDefaults.standard.string(forKey: "FTGAPIBaseURL")
			?? Bundle.main.object(forInfoDictionaryKey: "FTGAPIBaseURL") as? String
		return configured.flatMap(URL.init(string:)) ?? URL(string: "http://localhost:8000")!
	}

	var body: some View {
		List {
			switch model.state {
			case .loading:
				ProgressView().frame(maxWidth: .infinity)
			case let .failed(message):
				ContentUnavailableView {
					Label("Couldn't load your settings", systemImage: "wifi.exclamationmark")
				} description: {
					Text(message)
				} actions: {
					Button("Try again") { Task { await model.load() } }
				}
				.accessibilityIdentifier("settings.failed")
			case .loaded:
				loaded
			}
		}
		.navigationTitle("Settings")
		.sheet(isPresented: $editingDay) {
			NavigationStack { DayEditorView(model: model) }
		}
		.task { await model.load() }
		.refreshable { await model.load() }
		.accessibilityIdentifier("settings")
	}

	@ViewBuilder private var loaded: some View {
		if let problem = model.problem {
			Label(problem, systemImage: "exclamationmark.triangle.fill")
				.foregroundStyle(.red)
				.accessibilityIdentifier("settings.problem")
		}
		if let zone = model.zonePrompt, let upcoming = model.upcoming {
			zonePrompt(zone, current: upcoming.timeZone)
		}
		daySection
		remindersSection
		profileSection
		Section("Habits and tools") {
			NavigationLink("Habits") { HabitsView(environment: model.environment) }
				.accessibilityIdentifier("settings.habits")
			NavigationLink("API and MCP keys") { KeysView(model: keys) }
				.accessibilityIdentifier("settings.keys")
		}
		sessionsSection
		accountSection
	}

	// MARK: Sections

	private func zonePrompt(_ zone: String, current: String) -> some View {
		Section {
			VStack(alignment: .leading, spacing: 8) {
				Text("Your phone is in \(zone)")
					.font(.headline)
				Text("Your day runs on \(current). Switch to \(zone) from tomorrow?")
					.font(.subheadline)
					.foregroundStyle(.secondary)
				HStack {
					Button("Switch") { Task { await model.acceptZone() } }
						.buttonStyle(.borderedProminent)
						.accessibilityIdentifier("zone.switch")
					Button("Not now") { model.declineZone() }
						.buttonStyle(.bordered)
						.accessibilityIdentifier("zone.notNow")
				}
			}
			.padding(.vertical, 4)
		}
	}

	@ViewBuilder private var daySection: some View {
		if let account = model.account {
			Section {
				Button { editingDay = true } label: {
					LabeledContent("Today", value: "\(DayWindow.label(account.dayStart)) to \(DayWindow.label(account.dayEnd))")
				}
				.tint(.primary)
				.accessibilityIdentifier("day.edit")
				LabeledContent("Time zone", value: account.timeZone)
				if let pending = account.pending {
					Label {
						VStack(alignment: .leading, spacing: 2) {
							Text("From \(Self.dayName(pending.effectiveFrom))").fontWeight(.semibold)
							Text("\(DayWindow.label(pending.dayStart)) to \(DayWindow.label(pending.dayEnd)), \(pending.timeZone)")
						}
					} icon: {
						Image(systemName: "clock.arrow.circlepath")
					}
					.font(.subheadline)
					.foregroundStyle(.orange)
					.accessibilityElement(children: .combine)
					.accessibilityIdentifier("day.pending")
				}
			} header: {
				Text("Your day")
			} footer: {
				Text("The goose walks only between your day's start and end. A change starts tomorrow, so today keeps its hours.")
			}
		}
	}

	@ViewBuilder private var remindersSection: some View {
		if let reminders = model.reminders {
			Section {
				Toggle("Reminders", isOn: Binding(get: { reminders.enabled }, set: { on in Task { await model.setRemindersEnabled(on) } }))
					.disabled(model.working)
					.accessibilityIdentifier("reminders.enabled")
				if reminders.enabled {
					Stepper(
						"Warn below \(reminders.whenLeadBelow) steps",
						value: Binding(get: { reminders.whenLeadBelow }, set: { steps in Task { await model.setThreshold(steps) } }),
						in: 5 ... 95, step: 5
					)
					.accessibilityIdentifier("reminders.threshold")
					Toggle("Quiet hours", isOn: Binding(
						get: { reminders.quietHours != nil },
						set: { on in Task { await model.setQuietHours(on ? QuietHours(start: "22:00", end: "07:00") : nil) } }
					))
					.accessibilityIdentifier("reminders.quiet")
					if let quiet = reminders.quietHours {
						quietPicker("From", value: quiet.start) { QuietHours(start: $0, end: quiet.end) }
						quietPicker("Until", value: quiet.end) { QuietHours(start: quiet.start, end: $0) }
					}
				}
				if let notice = model.pushNotice {
					Text(notice)
						.font(.footnote)
						.foregroundStyle(.orange)
						.accessibilityIdentifier("reminders.notice")
				}
			} header: {
				Text("Reminders")
			} footer: {
				Text("At most three a day: when the lead drops below your number, an hour before the goose would catch you, and an hour before the day ends if you're not done. None in quiet hours.")
			}
		}
	}

	private func quietPicker(_ title: String, value: String, change: @escaping (String) -> QuietHours) -> some View {
		Picker(title, selection: Binding(get: { value }, set: { time in Task { await model.setQuietHours(change(time)) } })) {
			ForEach(DayWindow.options(including: value), id: \.self) { Text(DayWindow.label($0)).tag($0) }
		}
	}

	@ViewBuilder private var profileSection: some View {
		if let profile = model.profile {
			Section {
				Toggle("Public profile", isOn: Binding(get: { profile.isPublic }, set: { on in Task { await model.saveProfile(isPublic: on) } }))
					.disabled(model.working)
					.accessibilityIdentifier("profile.public")
				HStack {
					Text("Handle")
					TextField("your-name", text: $model.handleDraft)
						.multilineTextAlignment(.trailing)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.onSubmit { Task { await model.saveProfile(isPublic: profile.isPublic) } }
						.accessibilityIdentifier("profile.handle")
					if model.handleDraft != (profile.handle ?? "") {
						Button("Save") { Task { await model.saveProfile(isPublic: profile.isPublic) } }
							.buttonStyle(.borderless)
							.accessibilityIdentifier("profile.save")
					}
				}
				if let problem = model.profileProblem {
					Text(problem)
						.font(.footnote)
						.foregroundStyle(.red)
						.accessibilityIdentifier("profile.problem")
				}
				if let url = model.profileURL {
					Link(destination: url) {
						Label(url.absoluteString, systemImage: "safari")
					}
					.accessibilityIdentifier("profile.url")
				}
			} header: {
				Text("Public profile")
			} footer: {
				Text("Shows your name, streak, where the goose is and your last 35 days. Never your habits, amounts, log times or your day's hours.")
			}
		}
	}

	private var sessionsSection: some View {
		Section {
			ForEach(model.sessions) { item in
				VStack(alignment: .leading, spacing: 2) {
					Text(item.current ? "\(item.deviceName) (this phone)" : item.deviceName)
					Text("Last used \(item.lastUsedAt.formatted(date: .abbreviated, time: .omitted))")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.accessibilityElement(children: .combine)
				.swipeActions {
					if !item.current {
						Button("Sign out", role: .destructive) { Task { await model.revoke(item) } }
					}
				}
			}
		} header: {
			Text("Signed in on")
		} footer: {
			Text("Swipe another device to sign it out.")
		}
	}

	private var accountSection: some View {
		Section {
			Button("Sign out", role: .destructive) { confirmingSignOut = true }
				.accessibilityIdentifier("settings.signOut")
				.confirmationDialog("Sign out of Feed the Goose?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
					Button("Sign out", role: .destructive) {
						Task {
							await model.prepareSignOut()
							await session.signOut()
						}
					}
				} message: {
					Text("The widgets and Shortcuts stop working until you sign in again.")
				}
			Button("Delete account", role: .destructive) { confirmingDelete = true }
				.disabled(model.working)
				.accessibilityIdentifier("settings.delete")
				.alert("Delete your account?", isPresented: $confirmingDelete) {
					Button("Delete everything", role: .destructive) {
						Task {
							if await model.deleteAccount() { await session.signOut() }
						}
					}
					Button("Cancel", role: .cancel) {}
				} message: {
					Text("Every habit, log, day, key and session is removed, and your profile page goes away. This can't be undone.")
				}
		} footer: {
			if let account = model.account {
				Text("Signed in as \(account.email)")
			}
		}
	}

	/// The date a pending change starts, such as "Nov 27, 2026".
	static func dayName(_ date: LocalDate) -> String {
		let style = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
		guard let day = try? style.parse(date.rawValue) else { return date.rawValue }
		return day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
	}
}
