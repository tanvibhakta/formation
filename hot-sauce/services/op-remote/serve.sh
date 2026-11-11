#!/bin/zsh
# Hermes starts this as its `op-remote` MCP server, as the hidden user _opremote:
#   sudo -n -u _opremote /opt/op-remote/serve.sh
# It loads the 1Password session signin.sh saved, reads the approval bot's Telegram
# credentials, and runs the patched op-remote. op-remote reads a secret only after
# Tanvi taps Approve in Telegram.
set -euo pipefail
export HOME=/var/opremote
export PATH=/opt/op-remote/bin:/usr/bin:/bin
export OP_REMOTE_SOCK_DIR=$HOME/run

if [[ ! -r $HOME/session ]]; then
  print -u2 "op-remote: no 1Password session. Run: ssh -t Tanvis-MacBook-Pro.local sudo -u _opremote /opt/op-remote/signin.sh"
  exit 1
fi
# session holds two lines: the account shorthand, then the session token.
{ read -r shorthand; read -r token } < $HOME/session
export "OP_SESSION_${shorthand}=${token}"
unset token

cd $HOME
exec op run --no-masking --env-file=/opt/op-remote/telegram.env -- \
  bun /opt/op-remote/lib/cli.js serve --env-file=$HOME/run/secrets.env.tpl
