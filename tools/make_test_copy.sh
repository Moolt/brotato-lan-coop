#!/usr/bin/env bash
# Builds a throwaway copy of the decompiled game for testing the mod (see docs/lan-coop-plan.md,
# "Verification"). Usage: tools/make_test_copy.sh <target dir>, e.g. <scratchpad>/game.
# The copy uses its own user dir (BrotatoLanTest), has vsync off, and links the mod and
# tools/lan_test_driver.gd (as the LanTestDriver autoload) back into this repo, so edits apply.
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

project="$target/project.godot"
sed -i '/^\[application\]/a config/custom_user_dir_name="BrotatoLanTest"' "$project"
sed -i '/^OS_Seaven=/a LanTestDriver="*res://lan_test_driver.gd"' "$project"
sed -i '/^\[display\]/a window/vsync/use_vsync=false' "$project"
echo "Test copy ready: $target"
