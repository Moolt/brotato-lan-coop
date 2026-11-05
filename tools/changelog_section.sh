#!/usr/bin/env bash
# Prints the CHANGELOG.md section of one version (without its heading): the release notes of
# that version. Fails when the section is missing or empty.
# Usage: tools/changelog_section.sh 1.13.0   (also "v1.13.0" or "Unreleased")
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?usage: $0 <version>}"
version="${version#v}"
section="$(awk -v v="$version" '
	/^## \[/ { if (found) exit; found = index($0, "## [" v "]") == 1; next }
	/^\[[^]]*\]: / { if (found) exit }
	found { print }
' "$repo/CHANGELOG.md" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"
if [ -z "$section" ]; then
	echo "CHANGELOG.md has no section for $version (a heading \"## [$version] - <date>\")" >&2
	exit 1
fi
printf '%s\n' "$section"
