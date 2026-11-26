#!/usr/bin/env bash
# Generates the Swift client from clients/openapi.json into GooseAPI's Generated/ folder, and
# copies clients/fixtures into GooseCore, which bundles them for the fakes. With --check, writes
# both into a temporary folder and fails when the committed copies differ.
# Runs swift-openapi-generator as a command (pinned in Packages/GooseAPI/Generator), so builds
# need no plugin trust (TDD §6.2).
set -euo pipefail

ios="$(cd "$(dirname "$0")/.." && pwd)"
clients="$ios/.."
package="$ios/Packages/GooseAPI"
generated="$package/Sources/GooseAPI/Generated"
fixtures="$ios/Packages/GooseCore/Sources/GooseCore/Fixtures"

client_out="$generated"
fixtures_out="$fixtures"
if [ "${1:-}" = "--check" ]; then
	scratch="$(mktemp -d)"
	trap 'rm -rf "$scratch"' EXIT
	client_out="$scratch/Generated"
	fixtures_out="$scratch/Fixtures"
fi

swift build --package-path "$package/Generator" -c release --product swift-openapi-generator >&2
generator="$(swift build --package-path "$package/Generator" -c release --show-bin-path)/swift-openapi-generator"

rm -rf "$client_out" "$fixtures_out"
mkdir -p "$client_out"
"$generator" generate \
	--config "$package/openapi-generator-config.yaml" \
	--output-directory "$client_out" \
	"$clients/openapi.json" >&2
cp -R "$clients/fixtures" "$fixtures_out"

if [ "${1:-}" = "--check" ]; then
	stale=0
	diff -ru "$generated" "$client_out" || stale=1
	diff -ru "$fixtures" "$fixtures_out" || stale=1
	if [ "$stale" = 1 ]; then
		echo "The committed Swift client or fixture copy is stale. Run: just ios-generate-api" >&2
		exit 1
	fi
	echo "The committed Swift client and fixture copy match clients/openapi.json and clients/fixtures."
fi
