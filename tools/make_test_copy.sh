#!/usr/bin/env bash
# Builds a throwaway copy of the decompiled game for testing the mod (see docs/testing.md).
# Usage: tools/make_test_copy.sh <target dir>, e.g. <scratchpad>/game.
# The copy uses its own user dir (BrotatoLanTest), has vsync off, and links the mod and
# tools/lan_test_driver.gd (as the LanTestDriver autoload) back into this repo, so edits apply.
# It also adds the Abyssal Terrors DLC from its decompiled sources (../BrotatoAbyssalTerrors_Decompiled
# next to the repo) when they exist; NO_DLC=1 leaves it out (a copy without the DLC).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
vanilla="$repo/../Decompiled"
target="${1:?usage: $0 <target dir>}"

if [ -e "$target" ]; then
	echo "$target already exists" >&2
	exit 1
fi
cp -a "$vanilla" "$target"
rm -rf "$target/.git"
rm -f "$target/mods-unpacked/Moolt-Lan_Coop" "$target/CLAUDE.md" "$target/docs"
ln -s "$repo/mods-unpacked/Moolt-Lan_Coop" "$target/mods-unpacked/Moolt-Lan_Coop"
ln -s "$repo/tools/lan_test_driver.gd" "$target/lan_test_driver.gd"
# The DLC as sources, not its .pck: in this Godot build a loaded pack takes over all res://
# directory access (only the pack's folders exist, dir_exists is always false), so vanilla never
# finds the pack's dlcs/ folder. The DLC's scripts also need its global classes in project.godot.
dlc="$repo/../BrotatoAbyssalTerrors_Decompiled"
if [ -d "$dlc/dlcs" ] && [ "${NO_DLC:-}" != "1" ]; then
	cp -a "$dlc/dlcs" "$target/dlcs"
	cp -a "$dlc/.import/." "$target/.import/"
	# The DLC's class lists hold the base game's classes plus its own.
	classes="$(sed -n '/^_global_script_classes=/,/^\[application\]/p' "$dlc/project.godot" | sed '$d')"
	{
		sed -n '1,/^_global_script_classes=/p' "$target/project.godot" | sed '$d'
		printf '%s\n\n' "$classes"
		sed -n '/^\[application\]/,$p' "$target/project.godot"
	} > "$target/project.godot.new"
	mv "$target/project.godot.new" "$target/project.godot"
	# Without the classes whose scripts the decompile lacks (the DLC's tests).
	python3 -I - "$target" <<'PY'
import os, re, sys
target = sys.argv[1]
path = os.path.join(target, "project.godot")
text = open(path).read()
def keep(m):
	script = m.group(1)[len("res://"):]
	return m.group(0) if os.path.exists(os.path.join(target, script)) else ""
text = re.sub(r'\{\n"base": "[^"]*",\n"class": "[^"]*",\n"language": "[^"]*",\n"path": "([^"]*)"\n\}, ?', keep, text)
open(path, "w").write(text)
PY
	echo "Added the DLC from $dlc"
fi

project="$target/project.godot"
sed -i '/^\[application\]/a config/custom_user_dir_name="BrotatoLanTest"' "$project"
sed -i '/^OS_Seaven=/a LanTestDriver="*res://lan_test_driver.gd"' "$project"
sed -i '/^\[display\]/a window/vsync/use_vsync=false' "$project"
echo "Test copy ready: $target"
