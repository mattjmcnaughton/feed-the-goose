import Foundation
import GooseCore
import GooseRig
import SwiftUI

/// The chase scene: the still pose for the day's state, or the clip a change deserves while it
/// plays. Clips hold their last frame, so Feast and Peck end on the complete and caught scenes.
struct TodayScene: View {
	let snapshot: ChaseSnapshot
	let playing: TodayModel.Playing?
	let date: Date
	let timeZone: TimeZone
	let onFinish: (TodayModel.Playing) -> Void

	private var stage: Stage { Stage(rawValue: snapshot.chase.streak.stage) ?? .gosling }

	var body: some View {
		Group {
			if let playing {
				ClipPlayer(clip: clip(for: playing), start: playing.start)
					.task(id: playing.start) {
						try? await Task.sleep(for: .seconds(clip(for: playing).duration))
						onFinish(playing)
					}
			} else {
				SceneCanvas(pose: still)
			}
		}
		.frame(height: 250)
		.accessibilityElement()
		.accessibilityLabel(TodayText.sceneLabel(snapshot, at: date, stageName: stage.name))
		.accessibilityAddTraits(.isImage)
		.accessibilityIdentifier("today.scene")
	}

	/// The scene's lead is a share of a day's head start: 1 is 100 steps.
	private func share(_ steps: Double) -> Double { steps / 100 }

	private var hour: Double { TodayScene.hour(of: date, in: timeZone) }

	private var still: Pose {
		let chase = snapshot.chase
		switch chase.state {
		case .running: return .running(lead: share(snapshot.clock.lead(at: date)), hour: hour, stage: stage)
		case .short: return .short(lead: share(chase.lead), hour: hour, stage: stage)
		case .complete: return .complete(lead: share(chase.lead), hour: hour, stage: stage)
		case .caught: return .caught(hour: hour, stage: stage)
		}
	}

	private func clip(for playing: TodayModel.Playing) -> GooseRig.Clip {
		let stage = Stage(rawValue: playing.stage) ?? .gosling
		switch playing.clip {
		case .snap:
			return GooseRig.Clip.snap(from: share(playing.fromLead), to: share(snapshot.clock.lead(at: date)), hour: hour, stage: stage)
		case .feast:
			return GooseRig.Clip.feast(lead: share(snapshot.chase.lead), hour: hour, stage: stage)
		case .peck:
			return GooseRig.Clip.peck(lead: share(playing.fromLead), hour: hour, stage: stage)
		}
	}

	/// The sky's hour: the local time of day, from dawn (6) to midnight (24). The small hours,
	/// which belong to the night, are drawn as midnight.
	static func hour(of date: Date, in timeZone: TimeZone) -> Double {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		let parts = calendar.dateComponents([.hour, .minute], from: date)
		let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
		return hour < 6 ? 24 : hour
	}
}
