#!/usr/bin/env bash
# Prints the UDID of the pinned simulator: the device named $1 on iOS runtime $2.
set -euo pipefail
name="$1"
runtime="$2"
udid="$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name, runtime = sys.argv[1], "com.apple.CoreSimulator.SimRuntime.iOS-" + sys.argv[2].replace(".", "-")
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name:
        print(device["udid"])
        break
' "$name" "$runtime")"
if [ -z "$udid" ]; then
	echo "No available simulator named \"$name\" on iOS $runtime. Start the Mac with image macos-26." >&2
	exit 1
fi
echo "$udid"
