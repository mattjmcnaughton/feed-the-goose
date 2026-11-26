import GooseRig
import SwiftUI

/// The sign-in screen: the scene, an email field and one button. In debug builds the email goes
/// to the dev sign-in; an email off the allowlist is refused with a message that says so.
struct SignInView: View {
	@State private var model: SignInModel
	@FocusState private var emailFocused: Bool

	init(model: SignInModel) {
		_model = State(initialValue: model)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				SceneCanvas(pose: .running(lead: 0.55, hour: 9, stage: .goose))
					.frame(height: 220)
				Rectangle().fill(SignInPalette.ink).frame(height: 3)
				VStack(alignment: .leading, spacing: 18) {
					VStack(alignment: .leading, spacing: 6) {
						Text("Feed the Goose")
							.font(.custom("Shrikhand-Regular", size: 34, relativeTo: .largeTitle))
							.accessibilityAddTraits(.isHeader)
						Text("Do your habits to stay ahead of the goose.")
							.font(.body)
					}
					if let notice = model.notice, model.state == .idle {
						Callout(text: notice, tone: .info)
							.accessibilityIdentifier("signIn.notice")
					}
					form
					message
					if let server = model.server {
						Text("Dev sign-in · \(server)")
							.font(.footnote)
							.foregroundStyle(.secondary)
							.accessibilityIdentifier("signIn.server")
					}
				}
				.padding(20)
			}
			.foregroundStyle(SignInPalette.ink)
		}
		.scrollBounceBehavior(.basedOnSize)
		.background(SignInPalette.paper)
		.ignoresSafeArea(edges: .top)
	}

	@ViewBuilder private var form: some View {
		VStack(alignment: .leading, spacing: 12) {
			TextField("Email", text: $model.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(.secondary))
				.textContentType(.emailAddress)
				.keyboardType(.emailAddress)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.submitLabel(.go)
				.focused($emailFocused)
				.onSubmit { Task { await model.submit() } }
				.padding(.horizontal, 14)
				.frame(minHeight: 50)
				.background(.white, in: RoundedRectangle(cornerRadius: 14))
				.overlay(RoundedRectangle(cornerRadius: 14).stroke(SignInPalette.ink, lineWidth: 2))
				.disabled(model.state == .working || !model.isAvailable)
				.accessibilityLabel("Email")
				.accessibilityIdentifier("signIn.email")
			Button {
				emailFocused = false
				Task { await model.submit() }
			} label: {
				HStack(spacing: 10) {
					if model.state == .working {
						ProgressView().tint(SignInPalette.ink)
						Text("Signing in…")
					} else {
						Text("Sign in")
					}
				}
				.font(.headline)
				.frame(maxWidth: .infinity, minHeight: 50)
				.background(SignInPalette.bread, in: RoundedRectangle(cornerRadius: 14))
				.overlay(RoundedRectangle(cornerRadius: 14).stroke(SignInPalette.ink, lineWidth: 2))
				.opacity(model.canSubmit || model.state == .working ? 1 : 0.5)
			}
			.buttonStyle(.plain)
			.disabled(!model.canSubmit)
			.accessibilityIdentifier("signIn.submit")
		}
	}

	@ViewBuilder private var message: some View {
		switch model.state {
		case .idle, .working:
			if !model.isAvailable {
				Callout(text: "Sign-in isn't available in this build yet.", tone: .info)
			}
		case let .refused(email):
			Callout(
				title: "Not on the list yet",
				text: "\(email) isn't on the list of people who can sign in to Feed the Goose.",
				tone: .problem
			)
			.accessibilityIdentifier("signIn.refused")
		case let .failed(text):
			Callout(text: text, tone: .problem)
				.accessibilityIdentifier("signIn.failed")
		}
	}
}

/// The prototype's colours (docs/prototypes/04-app-screens).
enum SignInPalette {
	static let ink = Color(red: 0x1D / 255, green: 0x1A / 255, blue: 0x2F / 255)
	static let paper = Color(red: 0xFF / 255, green: 0xFA / 255, blue: 0xF0 / 255)
	static let bread = Color(red: 0xE8 / 255, green: 0xAE / 255, blue: 0x4C / 255)
	static let problem = Color(red: 0xD6 / 255, green: 0x3A / 255, blue: 0x1E / 255)
}

private struct Callout: View {
	enum Tone { case info, problem }

	var title: String?
	let text: String
	let tone: Tone

	var body: some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: tone == .problem ? "exclamationmark.triangle.fill" : "info.circle.fill")
				.foregroundStyle(tone == .problem ? SignInPalette.problem : SignInPalette.ink)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				if let title { Text(title).font(.headline) }
				Text(text).font(.subheadline)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(12)
		.background(
			tone == .problem ? SignInPalette.problem.opacity(0.1) : SignInPalette.ink.opacity(0.06),
			in: RoundedRectangle(cornerRadius: 12)
		)
		.accessibilityElement(children: .combine)
	}
}
