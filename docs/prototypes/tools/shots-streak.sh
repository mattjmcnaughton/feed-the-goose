#!/usr/bin/env bash
# Capture 06-streak-stakes at several streak lengths. Usage: tools/shots-streak.sh [width]
S=ftg-streak; source "$(dirname "$0")/lib.sh"
W=${1:-760}; OUT=$PROTO/screenshots/06-streak-stakes; mkdir -p "$OUT"
open_page 06-streak-stakes "$W"
go() {
	$AB eval "(()=>{document.querySelector('#dir [data-value=$1]').click(); const s=document.getElementById('streak'); s.value=$2; s.dispatchEvent(new Event('input')); return document.getElementById('title').textContent})()"
	$AB screenshot --full "$OUT/$1-day-$2.png" >/dev/null
}
for state in "grow 0" "grow 12" "grow 16" "grow 30" "fast 3" "fast 12" "nest 3" "nest 12"; do go $state; done
$AB errors 2>/dev/null | head -5
