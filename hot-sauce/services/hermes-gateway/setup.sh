#!/usr/bin/env bash

###############################################################################
# HERMES GATEWAY ON THE ALWAYS-ON MAC
#
# Run this from the laptop (the Hermes *client*). It installs Hermes on the
# always-on Mac over SSH, hands it this laptop's ~/.hermes, moves the Telegram
# gateway there, and removes the gateway from this laptop.
#
# Why move it: a Telegram bot token can be long-polled by exactly one process.
# Two gateways on one token fight (409 Conflict) and messages land on whichever
# grabbed them last. `hermes send` is a plain Bot API POST, so the laptop keeps
# sending notifications without a gateway of its own.
#
# Safe to run repeatedly. ~/.hermes data is copied only on the first run; after
# that the always-on Mac owns its sessions, memories and cron state, and a rerun
# must not clobber them with the laptop's stale copy. HERMES_RESYNC=1 forces it.
#
# Usage: ./setup.sh [ssh-host]      (default: Tanvis-MacBook-Pro.local)
###############################################################################

set -euo pipefail

HOST="${1:-Tanvis-MacBook-Pro.local}"
LOCAL_HOME="$HOME/.hermes"
LOCAL_HERMES="$LOCAL_HOME/hermes-agent/venv/bin/hermes"
REPO_URL="https://github.com/NousResearch/hermes-agent.git"

# Non-interactive SSH gets a bare PATH. The always-on Mac is Intel, so its
# Homebrew git/python live in /usr/local/bin; without this, /usr/bin/git is
# used and dies on the ssh-signing config in ~/.gitconfig.
REMOTE_PATH='$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
remote() { ssh -o BatchMode=yes "$HOST" "export PATH=$REMOTE_PATH; $1"; }

ok()   { printf "  [✓] %s\n" "$1"; }
warn() { printf "  [!] %s\n" "$1"; }
die()  { printf "  [✗] %s\n" "$1"; exit 1; }

###############################################################################
echo ""; echo "  ── Preflight ──"
[ -x "$LOCAL_HERMES" ] || die "No local Hermes at $LOCAL_HERMES"
remote true || die "Can't SSH to $HOST with a key"
ok "SSH to $HOST works"

# Run the same commit on both ends so the copied config/state matches the code.
COMMIT="$(git -C "$LOCAL_HOME/hermes-agent" rev-parse HEAD)"
ok "Pinning hermes-agent to local commit ${COMMIT:0:9}"

###############################################################################
echo ""; echo "  ── Install Hermes on $HOST ──"
remote "
  set -e
  mkdir -p ~/.hermes
  if [ ! -d ~/.hermes/hermes-agent/.git ]; then
    git clone --quiet $REPO_URL ~/.hermes/hermes-agent
  fi
  cd ~/.hermes/hermes-agent
  git fetch --quiet origin
  git checkout --quiet $COMMIT
"
ok "hermes-agent checked out at ${COMMIT:0:9}"

if remote '[ -x ~/.hermes/hermes-agent/venv/bin/hermes ]'; then
  ok "venv already built (delete ~/.hermes/hermes-agent/venv on $HOST to rebuild)"
else
  # setup-hermes.sh asks two y/n questions (ripgrep, setup wizard). Answer no
  # to both: config arrives from this laptop, so the wizard would only overwrite it.
  remote "cd ~/.hermes/hermes-agent && printf 'nn' | ./setup-hermes.sh"
  remote '[ -x ~/.hermes/hermes-agent/venv/bin/hermes ]' || die "setup-hermes.sh didn't produce a venv"
  ok "venv built"
fi

###############################################################################
echo ""; echo "  ── Stop the gateway on this laptop ──"
# Before copying data, so state.db isn't mid-write, and before the remote
# gateway starts, so the two never poll Telegram at the same time.
if [ -f "$HOME/Library/LaunchAgents/ai.hermes.gateway.plist" ] || pgrep -qf 'hermes_cli.main gateway'; then
  "$LOCAL_HERMES" gateway uninstall
  ok "Local gateway uninstalled"
else
  ok "No local gateway"
fi

###############################################################################
echo ""; echo "  ── Copy ~/.hermes ──"
if remote '[ -f ~/.hermes/config.yaml ]' && [ "${HERMES_RESYNC:-0}" != 1 ]; then
  ok "$HOST already has config.yaml; not overwriting its state (HERMES_RESYNC=1 to force)"
else
  # Excluded: the code (installed above), per-process runtime files, logs,
  # caches, and bin/ + lsp/, which hold arm64 binaries that won't run on Intel.
  rsync -a \
    --exclude hermes-agent/ --exclude bin/ --exclude lsp/ \
    --exclude logs/ --exclude cache/ --exclude image_cache/ --exclude audio_cache/ \
    --exclude checkpoints/ --exclude sandboxes/ --exclude backups/ --exclude cron/output/ \
    --exclude gateway.pid --exclude gateway.lock --exclude gateway_state.json \
    --exclude processes.json --exclude models_dev_cache.json \
    "$LOCAL_HOME/" "$HOST:.hermes/"
  ok "Copied ~/.hermes to $HOST"
fi

###############################################################################
echo ""; echo "  ── Start the gateway on $HOST ──"
# `gateway install` bakes the current PATH into the launchd plist, which is why
# REMOTE_PATH must already include /usr/local/bin here.
remote "cd ~/.hermes/hermes-agent && HERMES_HOME=\$HOME/.hermes venv/bin/hermes gateway install"
remote "cd ~/.hermes/hermes-agent && HERMES_HOME=\$HOME/.hermes venv/bin/hermes gateway start" || true

# Telegram connects a few seconds after launch; poll gateway_state.json for it.
CONNECTED=false
for _ in $(seq 1 30); do
  if remote "cat ~/.hermes/gateway_state.json 2>/dev/null" | python3 -c \
      'import json,sys; sys.exit(json.load(sys.stdin)["platforms"]["telegram"]["state"]!="connected")' 2>/dev/null; then
    CONNECTED=true; break
  fi
  sleep 2
done
$CONNECTED || die "Telegram never connected. Check ~/.hermes/logs/gateway.error.log on $HOST"
ok "Gateway on $HOST is connected to Telegram"

###############################################################################
echo ""; echo "  ── Client on this laptop ──"
"$LOCAL_HERMES" send --list telegram >/dev/null && ok "hermes send can reach Telegram from here"

echo ""
ok "Done. Gateway runs on $HOST; this laptop is client-only."
