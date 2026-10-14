#!/bin/bash

###############################################################################
# Keeps the vibechk main clone on origin/main. Run hourly by
# launchagents/com.tanvi.gitpull-vibechk.plist; safe to run by hand.
#
# launchd starts jobs with PATH=/usr/bin:/bin, where lefthook's post-merge
# `bun install` fails with "bun: command not found".
###############################################################################

set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
REPO="$HOME/Code/alt.inc/vibechk"

echo "── $(date '+%Y-%m-%d %H:%M:%S %z')"
cd "$REPO" || exit 1
git fetch -q origin main && git checkout -q main && git pull --ff-only -q origin main
status=$?
echo "exit=$status main=$(git rev-parse --short main) origin/main=$(git rev-parse --short origin/main)"
exit $status
