#!/usr/bin/env bash

###############################################################################
# Builds ~/.claude/settings.json from two sources:
#   settings.json          tracked, public — everything safe to publish
#   settings.private.json  gitignored — employer-specific config, e.g. the
#                          autoMode environment, which Claude Code only reads
#                          from the user-level file (not from a project's
#                          .claude/settings*.json), so it cannot live elsewhere
#
# The two are deep-merged (private wins; arrays are replaced, not concatenated)
# into a real file, not a symlink, so private values never land in the repo.
#
# Claude Code also edits ~/.claude/settings.json itself (/plugin, /config,
# "always allow" prompts). A rebuild would silently discard those edits, so the
# build records a hash and refuses to overwrite a file changed since. When that
# happens, copy the change into settings.json or settings.private.json, then
# rerun with --force.
#
# Usage: build-settings.sh [--force]
###############################################################################

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SRC_DIR/settings.json"
PRIVATE="$SRC_DIR/settings.private.json"
DST="$HOME/.claude/settings.json"
STAMP="$HOME/.claude/.settings.built.sha256"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

command -v jq >/dev/null || { echo "build-settings: jq is required" >&2; exit 1; }

if [ -f "$PRIVATE" ]; then
    MERGED=$(jq -s '.[0] * .[1]' "$BASE" "$PRIVATE")
else
    MERGED=$(jq . "$BASE")
fi

# Replacing the old symlink is safe: its target is the tracked base file.
if [ -L "$DST" ]; then
    rm "$DST"
elif [ -f "$DST" ] && ! $FORCE; then
    CURRENT=$(shasum -a 256 "$DST" | cut -d' ' -f1)
    if [ ! -f "$STAMP" ] || [ "$CURRENT" != "$(cat "$STAMP")" ]; then
        echo "build-settings: $DST was changed since the last build (likely by Claude Code)." >&2
        echo "Move these changes into settings.json or settings.private.json, then rerun with --force:" >&2
        diff <(printf '%s\n' "$MERGED") "$DST" >&2 || true
        exit 1
    fi
fi

mkdir -p "$(dirname "$DST")"
printf '%s\n' "$MERGED" > "$DST"
shasum -a 256 "$DST" | cut -d' ' -f1 > "$STAMP"
echo "build-settings: wrote $DST"
