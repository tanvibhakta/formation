#!/usr/bin/env bash

###############################################################################
# Snapshot Muesli's settings into hot-sauce/muesli/config.json.
# Run after changing a setting in Muesli, then commit the diff.
#
# Muesli keeps everything in one config.json, so this drops what must not be
# tracked: API keys (this repo is public), per-machine state (window position,
# calendar IDs, dismissed prompts), and one-time migration/onboarding flags.
###############################################################################

set -euo pipefail

SRC="$HOME/Library/Application Support/Muesli/config.json"
DST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.json"

jq --indent 2 'with_entries(select(.key | test(
    "api_key|anthropic_workspace_id|custom_llm_headers"
    + "|^contribution_|_migration_applied$|^has_completed_onboarding$"
    + "|^indicator_origin$|^disabled_calendar_ids$|^hidden_calendar_|^folder_order$"
    + "|^dictionary_suggestions$|^dismissed_|^show_ios_companion_prompt$|^marauders_map_unlocked$"
) | not))' "$SRC" > "$DST"

echo "Exported Muesli settings → $DST"
