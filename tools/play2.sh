#!/usr/bin/env bash
# Opens two game windows side by side for a manual test (see docs/testing.md): left at x 0,
# right at x 1280, 1280x720 each, the test driver idle. Host in one, join from the other.
# Usage: tools/play2.sh [game copy dir]  (default ~/.cache/brotato-lan-test/game; built with
# tools/make_test_copy.sh if missing). Env: GODOT (the Godot 3.7 binary), WIDTH, HEIGHT.
# Logs go to <game copy>/../logs/left.log and right.log. Windows already open are closed first.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
game="${1:-$HOME/.cache/brotato-lan-test/game}"
godot="${GODOT:-$repo/../Godot/Godot_v3.7-dev1_x11.64}"
width="${WIDTH:-1280}"
height="${HEIGHT:-720}"

if [ ! -x "$godot" ]; then
	echo "Godot binary not found: $godot (set GODOT)" >&2
	exit 1
fi
if [ ! -f "$game/project.godot" ]; then
	mkdir -p "$(dirname "$game")"
	"$repo/tools/make_test_copy.sh" "$game"
fi
logs="$(dirname "$game")/logs"
mkdir -p "$logs"

# Only instances of this copy ("[.]" keeps pkill from matching this script's own command line).
pkill -f "$(basename "$godot" | sed 's/^./[&]/') --path $game( |$)" 2>/dev/null && sleep 1 || true

nohup "$godot" --path "$game" --resolution "${width}x${height}" --position 0,0 > "$logs/left.log" 2>&1 &
sleep 1
nohup "$godot" --path "$game" --resolution "${width}x${height}" --position "$width,0" > "$logs/right.log" 2>&1 &
echo "Two windows started. Logs: $logs/left.log, $logs/right.log"
echo "Check for mod errors: grep -n 'SCRIPT ERROR' -A1 $logs/*.log"
