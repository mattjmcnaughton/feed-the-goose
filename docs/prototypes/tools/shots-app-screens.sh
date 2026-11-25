#!/usr/bin/env bash
# Capture every state of 04-app-screens. Usage: tools/shots-app-screens.sh [width]
S=ftg-app; source "$(dirname "$0")/lib.sh"
W=${1:-760}; OUT=$PROTO/screenshots/04-app-screens; mkdir -p "$OUT"
open_page 04-app-screens "$W"
shot() { js "new Promise(r=>setTimeout(r,${2:-900}))"; $AB screenshot "#phone" "$OUT/$1.png" >/dev/null; }
seg() { $AB click "#$1 [data-value=$2]" >/dev/null; }
tap() { js "document.querySelector('#phone [data-k=$1]').click()"; }
settime() { js "(()=>{const t=document.getElementById('time');t.value=$1;t.dispatchEvent(new Event('input'))})()"; }
say() { $AB eval "(document.querySelector('#phone .head, #phone .widget b')?.textContent ?? '')+' | '+(document.querySelector('#phone .sub, #phone .note, #phone .empty')?.textContent ?? '').replace(/\\s+/g,' ')"; }

shot today-part-fed; say
tap chunk-read; shot today-after-a-crust; say
tap rest-push; tap rest-read; shot today-fed; say
seg cond part; settime 24; shot today-short-at-midnight; say
seg cond none; shot today-unfed-6pm; say
settime 24; shot today-caught; say
seg cond none; settime 9; shot today-morning; say
seg cond part; seg screen out; shot widget; say
tap say-push; shot widget-siri; say
tap w-read; shot widget-tap; say
seg cond full; shot widget-fed; say
seg cond part; seg screen profile; shot profile; say
seg cond full; shot profile-fed; say
seg cond none; settime 24; shot profile-caught; say
seg cond part; settime 24; shot profile-short; say
$AB errors 2>/dev/null | head -5
