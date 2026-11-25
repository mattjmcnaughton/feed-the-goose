# Shared setup for the capture scripts. Source it after setting S (a short session name).
set -uo pipefail
PROTO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AB="agent-browser --session $S"
trap '$AB close >/dev/null 2>&1 || true' EXIT
# open_page <name> <width>: open a built prototype at 2x.
open_page() {
	test -f "$PROTO/$1.html" || { echo "Missing $1.html. Run python3 docs/prototypes/build.py first." >&2; exit 1; }
	$AB open "file://$PROTO/$1.html" >/dev/null
	$AB set viewport "$2" 1000 2 >/dev/null
}
js() { $AB eval "$1" >/dev/null; }
