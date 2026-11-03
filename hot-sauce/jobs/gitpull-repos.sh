#!/bin/bash

###############################################################################
# Keeps the main clone of each repo below on origin/main. Run hourly by
# launchagents/com.tanvi.gitpull-repos.plist; safe to run by hand.
#
# To track another repo, add its path to REPOS. A repo that fails does not stop
# the others; the job exits non-zero if any of them failed.
#
# launchd starts jobs with PATH=/usr/bin:/bin, where lefthook's post-merge
# `bun install` fails with "bun: command not found".
###############################################################################

set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPOS=(
    "$HOME/Code/alt.inc/into"
    "$HOME/Code/alt.inc/into-software-factory"
    "$HOME/Code/tanvibhakta.in"
    "$HOME/Code/formation"
)

overall=0
echo "── $(date '+%Y-%m-%d %H:%M:%S %z')"
for repo in "${REPOS[@]}"; do
    if ! cd "$repo"; then
        overall=1
        continue
    fi
    # These clones are also worked in, so never move someone off their branch.
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$branch" != "main" ]; then
        echo "$(basename "$repo"): skipped, on $branch"
        continue
    fi
    git fetch -q origin main && git pull --ff-only -q origin main
    status=$?
    [ "$status" -eq 0 ] || overall=$status
    echo "$(basename "$repo"): exit=$status main=$(git rev-parse --short main) origin/main=$(git rev-parse --short origin/main)"
done
exit $overall
