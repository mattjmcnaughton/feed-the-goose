#!/usr/bin/env bash
# Records the end-to-end demo one scene at a time on the Mac (TDD §8, docs/technical/demo.md).
#
#   scripts/demo/scene.sh setup     erase and boot the simulator, build the app and DemoTests
#   scripts/demo/scene.sh 1 ... 9   record one scene to $FTG_DEMO_OUT/scene-N.mp4 (not 6: the
#                                   profile is captured on the orb)
#   scripts/demo/scene.sh gallery   the Settings and Shortcuts screenshots, not recorded
#
# Run the scenes in order, on one simulator, with the orb's backend forwarded to port 8000.
# Screenshots land in $FTG_DEMO_OUT too. A scene that needs a step on the orb writes
# $FTG_DEMO_DIR/cue-<name> and waits for go-<name>; this script prints what to do. The `push`
# cue is handled here: it reads GET /dev/pushes and delivers the payload with simctl.
set -euo pipefail
cd "$(dirname "$0")/../.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(cat .xcode-version)/Contents/Developer}"
base="http://localhost:8000"
out="${FTG_DEMO_OUT:-/tmp/ftg-demo-out}"
cues="${FTG_DEMO_DIR:-/tmp/ftg-demo}"
bundle="com.mattjmcnaughton.feedthegoose"
mkdir -p "$out" "$cues"
udid="$(scripts/simulator-udid.sh 'iPhone 17 Pro' 26.2)"

status="$(curl -s -o /dev/null -w '%{http_code}' "$base/readyz" || true)"
echo "GET $base/readyz -> $status"
[ "$status" = 200 ] || { echo "No backend at $base; see docs/technical/demo.md." >&2; exit 1; }

xcodebuild_args=(-project FeedTheGoose.xcodeproj -scheme FeedTheGoose
	-destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/DerivedData)

run_tests() {
	TEST_RUNNER_FTG_DEMO=1 TEST_RUNNER_FTG_CAPTURE_DIR="$out" TEST_RUNNER_FTG_DEMO_DIR="$cues" \
		xcodebuild test-without-building "${xcodebuild_args[@]}" "$@"
}

# Answers cues while the test runs: `push` here, the others by whoever runs the demo.
# A scene's first cue is `record`: the clip starts when the test is ready, not while
# xcodebuild starts up. $1 is the clip, or empty for no recording.
answer_cues() {
	local clip="$1" seen=""
	while sleep 0.5; do
		for cue in "$cues"/cue-*; do
			[ -e "$cue" ] || continue
			local name="${cue##*/cue-}"
			case "$name" in
			record)
				if [ -n "$clip" ] && [ ! -e "$cues/recorder.pid" ]; then
					xcrun simctl io "$udid" recordVideo --codec h264 --force "$clip" >"$clip.log" 2>&1 &
					echo $! >"$cues/recorder.pid"
					sleep 2
				fi
				touch "$cues/go-record"
				;;
			push)
				local payload
				payload="$(curl -s "$base/dev/pushes?email=remind@example.com&limit=1" | jq -c '.[0].payload // empty')"
				if [ -n "$payload" ]; then
					echo "$payload" >"$cues/push.json"
					echo "GET /dev/pushes -> $payload"
					xcrun simctl push "$udid" "$bundle" "$cues/push.json"
					touch "$cues/go-push"
				fi
				;;
			*)
				if [ "$seen" != "$name" ]; then
					echo ">>> Cue '$name': run \`scripts/demo/orb.sh $name\` on the orb, then \`touch $cues/go-$name\` here."
					seen="$name"
				fi
				;;
			esac
		done
	done
}

# Stops the recorder and waits for it to finish writing the clip.
stop() {
	kill "$answerer" 2>/dev/null || true
	if [ -e "$cues/recorder.pid" ]; then
		local pid
		pid="$(cat "$cues/recorder.pid")"
		kill -INT "$pid" 2>/dev/null || true
		while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
		rm -f "$cues/recorder.pid"
	fi
}

case "${1:-}" in
setup)
	xcodegen generate --spec project.yml
	xcrun simctl shutdown "$udid" 2>/dev/null || true
	xcrun simctl erase "$udid"
	xcrun simctl boot "$udid"
	xcrun simctl bootstatus "$udid"
	rm -f "$cues"/cue-* "$cues"/go-*
	xcodebuild build-for-testing -quiet "${xcodebuild_args[@]}"
	;;
gallery)
	answer_cues "" &
	answerer=$!
	trap stop EXIT
	run_tests -only-testing:FeedTheGooseUITests/DemoTests/test5bSettingsGallery \
		-only-testing:FeedTheGooseUITests/DemoTests/test5cShortcutsGallery
	;;
[1-9])
	case "$1" in
	1) test=test1SignInAndSetUp ;;
	2) test=test2LogAndUndo ;;
	3) test=test3Widgets ;;
	4) test=test4MCP ;;
	5) test=test5Fed ;;
	6) echo "Scene 6 is the profile page, captured on the orb: scripts/demo/orb.sh profile" >&2; exit 2 ;;
	7) test=test7Caught ;;
	8) test=test8Offline ;;
	9) test=test9Reminder ;;
	esac
	rm -f "$cues/recorder.pid"
	answer_cues "$out/scene-$1.mp4" &
	answerer=$!
	trap stop EXIT
	run_tests -only-testing:"FeedTheGooseUITests/DemoTests/$test"
	;;
*)
	sed -n '2,12p' "$0" >&2
	exit 2
	;;
esac
