#!/usr/bin/env bash
# Packs the mod into dist/Moolt-Lan_Coop.zip (drop it into Brotato's mods/ folder).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
rm -f dist/Moolt-Lan_Coop.zip
zip -rq dist/Moolt-Lan_Coop.zip mods-unpacked/Moolt-Lan_Coop -x '*/.gitkeep'
echo "Built dist/Moolt-Lan_Coop.zip"
