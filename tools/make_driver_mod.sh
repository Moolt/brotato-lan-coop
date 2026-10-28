#!/usr/bin/env bash
# Packs tools/lan_test_driver.gd as a test-only mod, for a shipped game (Steam/GOG build, any OS)
# where there is no project.godot to add the LanTestDriver autoload to (see docs/testing.md).
# Usage: tools/make_driver_mod.sh <target zip>, e.g. <game>/mods/Moolt-LanTestDriver.zip.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:?usage: $0 <target zip>}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
dir="$tmp/mods-unpacked/Moolt-LanTestDriver"
mkdir -p "$dir"
cp "$repo/tools/lan_test_driver.gd" "$dir/lan_test_driver.gd"
cat > "$dir/manifest.json" <<'EOF'
{
  "name": "LanTestDriver",
  "namespace": "Moolt",
  "version_number": "0.0.1",
  "description": "Test driver for Moolt-Lan_Coop (test only)",
  "website_url": "",
  "dependencies": ["Moolt-Lan_Coop"],
  "extra": {
    "godot": {
      "authors": [],
      "tags": [],
      "description_rich": "",
      "optional_dependencies": [],
      "load_before": [],
      "incompatibilities": [],
      "compatible_mod_loader_version": ["6.3.0"],
      "compatible_game_version": ["1.1.15.4"],
      "config_schema": {}
    }
  }
}
EOF
cat > "$dir/mod_main.gd" <<'EOF'
extends Node

# Adds the driver to the root, where the test copy has it as the LanTestDriver autoload.
func _ready() -> void :
	var driver: Node = load(ModLoaderMod.get_unpacked_dir().plus_file("Moolt-LanTestDriver/lan_test_driver.gd")).new()
	driver.name = "LanTestDriver"
	get_tree().root.call_deferred("add_child", driver)
EOF
rm -f "$target"
target="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
(cd "$tmp" && zip -rq "$target" mods-unpacked)
echo "Built $target"
