#!/usr/bin/env bash

###############################################################################
# Snapshot the work vault's Obsidian settings into hot-sauce/obsidian/settings.
# Run after changing a setting in Obsidian, then commit the diff.
#
# Skips workspace*.json: open tabs and pane layout belong to one machine.
###############################################################################

set -euo pipefail

SRC="$HOME/Dropbox/work/.obsidian"
DST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/settings"

mkdir -p "$DST"
find "$DST" -maxdepth 1 -name '*.json' -delete
find "$SRC" -maxdepth 1 -name '*.json' ! -name 'workspace*.json' -exec cp {} "$DST/" \;

echo "Exported Obsidian settings → $DST"
