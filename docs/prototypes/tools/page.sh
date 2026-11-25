#!/usr/bin/env bash
# Capture the whole page of a prototype in its opening state.
# Usage: tools/page.sh <name> [width]     e.g. tools/page.sh 05-animations 360
S=ftg-page; source "$(dirname "$0")/lib.sh"
NAME=${1:?prototype name, such as 05-animations}; W=${2:-760}
OUT=$PROTO/screenshots/$NAME; mkdir -p "$OUT"
open_page "$NAME" "$W"
js "new Promise(r=>setTimeout(r,600))"
$AB screenshot --full "$OUT/page-$W.png" >/dev/null
$AB eval "document.documentElement.scrollWidth+' wide in a '+innerWidth+' viewport'"
$AB errors 2>/dev/null | head -5
