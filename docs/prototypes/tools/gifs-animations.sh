#!/usr/bin/env bash
# A looping GIF per clip of 05-animations, one frame per slider step, with the last frame held.
# Usage: tools/gifs-animations.sh [fps]     CLIPS="snap feast" limits the clips.
S=ftg-gifs; source "$(dirname "$0")/lib.sh"
FPS=${1:-15}; OUT=$PROTO/animations; TMP=$(mktemp -d); mkdir -p "$OUT"
open_page 05-animations 760
for clip in ${CLIPS:-snap forage bonk feast truce walk peck scuffle stare}; do
	js "document.querySelector('[data-value=$clip]').click()"
	DUR=$($AB eval "document.getElementById('scrub').max" | tr -d '"')
	N=$(awk "BEGIN{print int($DUR*$FPS)+1}")
	for i in $(seq 0 "$N"); do
		js "(()=>{const s=document.getElementById('scrub'); s.value=Math.min(s.max,$i/$FPS).toFixed(2); s.dispatchEvent(new Event('input'))})()"
		$AB screenshot ".stage" "$TMP/$clip-$(printf %03d "$i").png" >/dev/null
	done
	# Hold the last frame for a second before the loop restarts.
	ffmpeg -loglevel error -y -framerate "$FPS" -i "$TMP/$clip-%03d.png" \
		-vf "tpad=stop_mode=clone:stop_duration=1,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" \
		"$OUT/$clip.gif"
	echo "$clip.gif $(stat -c %s "$OUT/$clip.gif") bytes, $((N+1)) frames"
done
$AB errors 2>/dev/null | head -5
rm -rf "$TMP"
