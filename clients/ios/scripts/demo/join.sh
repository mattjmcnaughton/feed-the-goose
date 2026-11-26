#!/usr/bin/env bash
# Joins the scene clips into docs/demo/v1-demo.mp4, with a title card before each scene
# (TDD §8.3). Runs on the orb, which has ffmpeg and magick.
#
#   scripts/demo/join.sh CLIPS_DIR PROFILE_PNG [OUT]
#
# CLIPS_DIR holds scene-1.mp4 to scene-9.mp4 (no scene 6) copied from the Mac;
# PROFILE_PNG is scene 6, from `orb.sh profile`. 600 pixels wide, H.264, -crf 24.
set -euo pipefail
clips="${1:?the folder with scene-N.mp4}"
profile="${2:?the profile capture from orb.sh profile}"
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
out="${3:-$repo/docs/demo/v1-demo.mp4}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The simulator records 1206×2622; scale everything to 600 wide at 30 frames a second.
size="600x1304"
fit="scale=600:-2,pad=600:1304:(ow-iw)/2:(oh-ih)/2:color=0xF2EADB,fps=30,format=yuv420p,setsar=1"

# Scene number | speed | title | what it shows. Long waits play faster, and the card says so.
scenes=(
	"1|1|1. Sign in and set up|Dev sign-in as a new account, then three habits.\nThe server saves each one."
	"2|1|2. Log and undo|The seeded demo account: lead 80, 13-day streak.\n+10 pushups plays Snap and the lead rises.\nUndo takes it back; +10 again."
	"3|1|3. Widgets|The Chase and Feed widgets on the Home Screen.\n+5 reading on the Feed widget logs\nwithout opening the app; both redraw."
	"4|1|4. MCP|An MCP key made in Settings.\nFrom the orb, log_habit at /mcp logs 5 pages.\nThe app, brought forward, shows the log."
	"5|1|5. Fed|Finishing Pushups and Reading plays Feast.\nThe streak reaches 14 days."
	"6|1|6. Public profile|localhost:8000/matt in a browser on the orb.\nThe streak and the last 35 days,\nand no habit names."
	"7|2|7. Caught|A seeded account the goose catches\nabout a minute after seeding: Peck.\nPlayed at 2× speed."
	"8|1|8. Offline|The web service stops; a log is queued.\nThe service starts again and the log is sent\nwith the time it was made."
	"9|2|9. Reminder|Reminders on. The worker plans one and the\nrecording sender captures it. Its payload is\ndelivered with xcrun simctl push, not APNs.\nPlayed at 2× speed."
)

card() {
	magick -size "$size" xc:'#F2EADB' -fill '#1E1B2E' -gravity center \
		-font DejaVu-Sans-Bold -pointsize 40 -annotate +0-120 "$2" \
		-font DejaVu-Sans -pointsize 22 -interline-spacing 8 -annotate +0+40 "$(printf '%b' "$3")" \
		"$work/card-$1.png"
	ffmpeg -loglevel error -y -loop 1 -t 4 -i "$work/card-$1.png" -vf "$fit" -r 30 -c:v libx264 -crf 24 -an "$work/$1-a.mp4"
}

# The simulator's H.264 has B-frames whose decode times lag their presentation times by many
# seconds, and ffmpeg times frames by the decode time here, so resampling the clip drops whole
# stretches of it. Decode every frame in presentation order instead, and show each one until the
# next one's presentation time, divided by the speed.
retime() {
	local clip="$1" speed="$2" result="$3" frames="$work/frames"
	rm -rf "$frames" && mkdir "$frames"
	ffmpeg -loglevel error -y -i "$clip" -vf "setpts=N,scale=600:-2" -fps_mode passthrough -q:v 2 "$frames/%06d.jpg"
	ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$clip" | cut -d, -f1 |
		awk -v dir="$frames" -v speed="$speed" '
			{ t[NR] = $1 }
			END {
				for (i = 1; i <= NR; i++) {
					d = (i < NR ? t[i + 1] - t[i] : 1) / speed
					if (d < 0) d = 0
					printf "file '\''%s/%06d.jpg'\''\nduration %.4f\n", dir, i, d
				}
				printf "file '\''%s/%06d.jpg'\''\n", dir, NR
			}' >"$frames/list.txt"
	ffmpeg -loglevel error -y -f concat -safe 0 -i "$frames/list.txt" -vf "$fit" -r 30 -c:v libx264 -crf 24 -an "$result"
}

: >"$work/list.txt"
for entry in "${scenes[@]}"; do
	IFS='|' read -r n speed title text <<<"$entry"
	card "$n" "$title" "$text"
	if [ "$n" = 6 ]; then
		# The page is taller than its card; keep the card.
		magick "$profile" -crop 1200x1150+0+0 +repage "$work/profile.png"
		ffmpeg -loglevel error -y -loop 1 -t 8 -i "$work/profile.png" -vf "$fit" -r 30 -c:v libx264 -crf 24 -an "$work/$n-b.mp4"
	else
		retime "$clips/scene-$n.mp4" "$speed" "$work/$n-b.mp4"
	fi
	printf "file '%s'\nfile '%s'\n" "$work/$n-a.mp4" "$work/$n-b.mp4" >>"$work/list.txt"
done

mkdir -p "$(dirname "$out")"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$work/list.txt" -c copy -movflags +faststart "$out"
# Where each scene starts, for the script in docs/demo/README.md.
t=0
for entry in "${scenes[@]}"; do
	IFS='|' read -r n _ title _ <<<"$entry"
	printf '%s at %d:%02d\n' "$title" $((${t%.*} / 60)) $((${t%.*} % 60))
	for part in a b; do
		t="$(echo "$t + $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/$n-$part.mp4")" | bc)"
	done
done
printf '%s: %s, %d:%02d\n' "$out" "$(du -h "$out" | cut -f1)" $((${t%.*} / 60)) $((${t%.*} % 60))
