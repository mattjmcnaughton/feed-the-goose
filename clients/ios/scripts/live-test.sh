#!/usr/bin/env bash
# Runs LiveBackendTests against the orb's backend and records the simulator while it runs.
# Run it through `just ios-live-test`, which sets DEVELOPER_DIR and generates the project.
# The recording and the test's screenshots land in $FTG_CAPTURE_DIR (default /tmp/ftg-captures).
set -euo pipefail
cd "$(dirname "$0")/.."

base="http://localhost:8000"
captures="${FTG_CAPTURE_DIR:-/tmp/ftg-captures}"
mkdir -p "$captures"

# The forward works only if the orb's backend answers here, on the Mac.
status="$(curl -s -o /dev/null -w '%{http_code}' "$base/readyz" || true)"
echo "GET $base/readyz -> $status"
if [ "$status" != 200 ]; then
	echo "No backend at $base. In the orb run \`just dev\` with live@example.com in ALLOWED_EMAILS," >&2
	echo "and start the Mac with forward_ports [\"8000:8000\"]." >&2
	exit 1
fi

# A fresh simulator: no old session in the Keychain and no widgets on the Home Screen.
udid="$(scripts/simulator-udid.sh 'iPhone 17 Pro' 26.2)"
xcrun simctl shutdown "$udid" 2>/dev/null || true
xcrun simctl erase "$udid"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid"

xcrun simctl io "$udid" recordVideo --codec h264 --force "$captures/live-test.mp4" >/tmp/live-test-record.log 2>&1 &
recorder=$!
trap 'kill -INT $recorder 2>/dev/null; wait $recorder 2>/dev/null || true' EXIT
sleep 2

TEST_RUNNER_FTG_CAPTURE_DIR="$captures" xcodebuild test \
	-project FeedTheGoose.xcodeproj -scheme FeedTheGoose \
	-destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/DerivedData \
	-only-testing:FeedTheGooseUITests/LiveBackendTests
