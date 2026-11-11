#!/bin/zsh
# Lets Claude Code run over SSH on this laptop (Hermes uses this from the always-on Mac).
# Claude Code keeps its login in the macOS Keychain, and an SSH session can't unlock that Keychain,
# so over SSH `claude` reports loggedIn: false. A long-lived token from
# `claude setup-token` avoids that. This stores the token in a file only you can read;
# hot-sauce/dotfiles/zshenv exports it for SSH sessions only.
#
# Usage: run `claude setup-token` in a real terminal tab, then run this script and paste the token.
# Re-run it whenever the token expires (about a year) or is revoked.
set -euo pipefail

token_file="$HOME/.config/claude-ssh/oauth-token"

if [[ ! -t 0 ]]; then
  print -u2 "Run this in a terminal tab: it reads the token without echoing it."
  exit 1
fi

read -rs "token?Paste the token from 'claude setup-token': "
print
token=${token//[[:space:]]/}
# A double paste once produced two tokens glued together; `claude auth status` still said
# loggedIn: true, and only real requests failed with 401. So check for exactly one token.
if [[ ! "$token" =~ '^sk-ant-oat[0-9A-Za-z_-]+$' || "${token#sk-ant-*sk-ant-}" != "$token" ]]; then
  print -u2 "Expected exactly one token starting sk-ant-oat (was it pasted twice?). Nothing saved."
  exit 1
fi

umask 077
mkdir -p "${token_file:h}"
print -r -- "$token" > "$token_file"
chmod 600 "$token_file"
unset token
print "Saved to $token_file (mode 600)."

# `claude auth status` only proves a token is present, not that it is valid: make a real request.
print "Checking from the always-on Mac with a real request (expect: ok)..."
ssh -o ConnectTimeout=10 Tanvis-MacBook-Pro.local \
  'ssh -o BatchMode=yes -o ConnectTimeout=10 big-macbook "cd /tmp && /opt/homebrew/bin/claude -p \"Reply with just: ok\" --max-turns 1"'
