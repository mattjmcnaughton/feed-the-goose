#!/usr/bin/env bash
# A contact sheet per clip of 05-animations, stepped with the frame slider.
# Usage: tools/frames-animations.sh [frames-per-clip]     CLIPS="snap feast" limits the clips.
S=ftg-frames; source "$(dirname "$0")/lib.sh"
N=${1:-10}; OUT=$PROTO/animations; TMP=$(mktemp -d); mkdir -p "$OUT"
open_page 05-animations 760
for clip in ${CLIPS:-snap forage bonk feast truce walk peck scuffle stare}; do
	js "document.querySelector('[data-value=$clip]').click()"
	for i in $(seq 0 $((N-1))); do
		js "(()=>{const s=document.getElementById('scrub'); s.value=(s.max*$i/($N-1)).toFixed(2); s.dispatchEvent(new Event('input'))})()"
		$AB screenshot ".stage" "$TMP/$clip-$(printf %02d "$i").png" >/dev/null
	done
	magick montage "$TMP/$clip-"*.png -tile 5x -geometry 340x+4+4 -background '#888' -quality 88 "$OUT/$clip-frames.jpg"
	echo "$clip-frames.jpg"
done
$AB errors 2>/dev/null | head -5
rm -rf "$TMP"
