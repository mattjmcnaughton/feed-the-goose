#!/usr/bin/env bash
# The demo's steps outside the phone, run on the orb (TDD §8, docs/technical/demo.md).
#
#   scripts/demo/orb.sh backend        start dockerd, Postgres, the web service and the worker
#   scripts/demo/orb.sh mcp KEY        scene 4: tools/list, list_habits, then log_habit 5 pages
#                                      of Reading with the MCP key the app showed
#   scripts/demo/orb.sh offline        scene 8: stop the web service
#   scripts/demo/orb.sh online         scene 8: start it again, then show the stored log's time
#   scripts/demo/orb.sh profile        scene 6: capture /matt with agent-browser at 2x
#
# Transcripts and captures land in $FTG_DEMO_ORB_OUT (default .amp/in/artifacts/T20).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
out="${FTG_DEMO_ORB_OUT:-$repo/.amp/in/artifacts/T20}"
base="http://localhost:8000"
mkdir -p "$out"

# Every demo account, plus the ones the other UI tests use.
emails="you@example.com,live@example.com,new@example.com,matt@example.com,caught@example.com,offline@example.com,remind@example.com"
# Reminders 30 seconds ahead instead of an hour, so scene 9 fits in the recording.
# Uvicorn closes an idle connection after 5 seconds, and the satellite's port forward passes
# the close on late: the app then sends a PUT on a dead connection and iOS does not retry it
# (-1005). A longer keep-alive than the app's longest pause between requests avoids that.
web_command="cd $repo/backend && UVICORN_TIMEOUT_KEEP_ALIVE=300 ALLOWED_EMAILS=$emails REMINDER_BEFORE_SECONDS=30 just dev"
worker_command="cd $repo/backend && ENV=development ALLOWED_EMAILS=$emails REMINDER_BEFORE_SECONDS=30 just worker"

wait_ready() {
	for _ in $(seq 60); do
		[ "$(curl -s -o /dev/null -w '%{http_code}' "$base/readyz" || true)" = 200 ] && { echo "GET $base/readyz -> 200"; return; }
		sleep 1
	done
	echo "the web service did not come up" >&2
	exit 1
}

mcp() {
	curl -s -X POST "$base/mcp" -H "authorization: Bearer $1" -H 'content-type: application/json' \
		-H 'accept: application/json, text/event-stream' -d "$2"
}

# The session the demo user's app has is not ours; read the logs with our own.
session() {
	local identity
	identity="$(curl -s -X POST "$base/dev/token" -H 'content-type: application/json' -d "{\"email\":\"$1\"}" | jq -r .identity_token)"
	curl -s -X POST "$base/v1/auth/session" -H 'content-type: application/json' \
		-d "{\"auth0_access_token\":\"$identity\",\"time_zone\":\"America/New_York\",\"device_name\":\"demo orb\"}" | jq -r .session_token
}

case "${1:-}" in
backend)
	amp orb service start dockerd --command 'sudo dockerd' >/dev/null
	sleep 3
	(cd "$repo/backend" && DOCKER="sudo docker" just db-up && just migrate)
	amp orb service start web --command "$web_command" --port 8000 >/dev/null
	amp orb service start worker --command "$worker_command" >/dev/null
	wait_ready
	;;
mcp)
	key="${2:?the MCP key the app showed}"
	{
		echo '$ POST /mcp tools/list'
		mcp "$key" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq -c '[.result.tools[].name]'
		echo '$ POST /mcp tools/call list_habits'
		habits="$(mcp "$key" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_habits","arguments":{}}}')"
		echo "$habits" | jq -c '.result.structuredContent // .result.content'
		reading="$(echo "$habits" | jq -r '[.. | objects | select(.name? == {"untrusted":"Reading"} or .name? == "Reading") | .id // .habit_id][0]')"
		request="$(jq -nc --arg h "$reading" --arg k "$(uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())')" \
			'{jsonrpc:"2.0",id:3,method:"tools/call",params:{name:"log_habit",arguments:{habit_id:$h,amount:5,idempotency_key:$k}}}')"
		echo "$ POST /mcp $request"
		mcp "$key" "$request" | jq -c '.result.structuredContent // .result'
	} | tee "$out/scene-4-mcp.txt"
	;;
offline)
	amp orb service stop web
	echo "$(date -u +%FT%TZ) web stopped" | tee "$out/scene-8-offline.txt"
	;;
online)
	amp orb service start web --command "$web_command" --port 8000 >/dev/null
	wait_ready
	echo "$(date -u +%FT%TZ) web back" | tee -a "$out/scene-8-offline.txt"
	;;
logs)
	# After scene 8: the stored log's logged_at beside when the server came back.
	token="$(session offline@example.com)"
	date="$(curl -s "$base/v1/chase/today" -H "authorization: Bearer $token" | jq -r .date)"
	curl -s "$base/v1/logs?date=$date" -H "authorization: Bearer $token" |
		jq -c '.[] | {amount, source, logged_at, undone_at}' | tee -a "$out/scene-8-offline.txt"
	;;
profile)
	agent-browser open "$base/matt" >/dev/null
	agent-browser set viewport 600 1100 2 >/dev/null
	sleep 2
	agent-browser screenshot --full "$out/06-profile.png" >/dev/null
	curl -s "$base/matt" >"$out/06-profile.html"
	for name in Pushups Workout Reading; do
		if grep -qi "$name" "$out/06-profile.html"; then echo "habit name $name is on the page" >&2; exit 1; fi
	done
	echo "/matt captured; no habit name on it" | tee "$out/scene-6-profile.txt"
	;;
*)
	sed -n '2,12p' "$0" >&2
	exit 2
	;;
esac
