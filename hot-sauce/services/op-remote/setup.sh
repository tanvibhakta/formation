#!/bin/zsh
# Installs isolated op-remote for Hermes on the always-on Mac. Run from the laptop in a
# real terminal (sudo on the server asks for your password). Idempotent.
# Usage: hot-sauce/services/op-remote/setup.sh [ssh-host]
set -euo pipefail
here=${0:A:h}
host=${1:-Tanvis-MacBook-Pro.local}
stage=/tmp/op-remote-stage

ssh "$host" "rm -rf $stage && mkdir -m 700 $stage"
scp -q "$here"/{isolate.sh,patch.py,gen-secrets.py,serve.sh,signin.sh,op-remote,telegram.env} "$host:$stage/"

# Root part: hidden user, root-owned code, sudo rule.
ssh -t "$host" "sudo /bin/zsh $stage/isolate.sh $stage"
ssh "$host" "rm -rf $stage"

ssh "$host" zsh -s <<'REMOTE'
set -euo pipefail
# Point Hermes at the isolated server. Edited as text so config.yaml keeps its
# comments and order.
/usr/bin/python3 -I - <<'PY'
import os, re
p = os.path.expanduser("~/.hermes/config.yaml")
s = open(p).read()
entry = ('  op-remote:\n    command: /usr/bin/sudo\n'
         '    args: ["-n", "-u", "_opremote", "/opt/op-remote/serve.sh"]\n')
block = re.compile(r"^  op-remote:\n(?:    .*\n)*", re.M)
s = block.sub(entry, s, count=1) if block.search(s) else s.replace("\nmcp_servers:\n", "\nmcp_servers:\n" + entry, 1)
open(p, "w").write(s)
print("Hermes config points at /opt/op-remote/serve.sh as _opremote")
PY

# Remove the first, unisolated install: sign its session out, forget the account
# for this user, and drop the npm copies Hermes could edit.
old=~/.hermes/op-remote
if [[ -r $old/session ]]; then
  { read -r sh; read -r tok } < $old/session
  env "OP_SESSION_$sh=$tok" /usr/local/bin/op signout >/dev/null 2>&1 || true
fi
/usr/local/bin/op account forget my.1password.com >/dev/null 2>&1 || true
rm -rf $old
export PATH="$HOME/.nvm/versions/node/v24.21.0/bin:$PATH"
npm uninstall -g @wyattjoh/op-remote >/dev/null 2>&1 || true
print "Removed the unisolated install"
REMOTE

print "\nNext, sign _opremote into 1Password (Secret Key and password the first time):"
print "  ssh -t $host 'sudo -u _opremote /opt/op-remote/signin.sh && ~/.local/bin/hermes gateway restart'"
