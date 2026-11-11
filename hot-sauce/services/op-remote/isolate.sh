#!/bin/zsh
# Root half of the op-remote install on the always-on Mac. Run by setup.sh as:
#   ssh -t Tanvis-MacBook-Pro.local sudo /bin/zsh /tmp/op-remote-stage/isolate.sh /tmp/op-remote-stage
# Idempotent. It makes op-remote run as a hidden user, _opremote, from root-owned
# files, so Hermes (user tanvibhakta) can start it and talk to its socket but can't
# read its 1Password session or change its code.
set -euo pipefail
stage=${1:?usage: isolate.sh <stage-dir>}
hermes_user=tanvibhakta
svc=_opremote
id_num=420                       # below 500, so macOS treats it as a hidden system account
opt=/opt/op-remote
home=/var/opremote
[[ $EUID -eq 0 ]] || { print -u2 "run with sudo"; exit 1; }

# 1. Hidden service user and group.
if ! dscl . -read /Groups/$svc >/dev/null 2>&1; then
  dscl . -list /Groups PrimaryGroupID | awk -v n=$id_num '$2==n{exit 1}' || { print -u2 "GID $id_num taken"; exit 1; }
  dscl . -create /Groups/$svc PrimaryGroupID $id_num
  dscl . -create /Groups/$svc RealName "op-remote service"
fi
if ! dscl . -read /Users/$svc >/dev/null 2>&1; then
  dscl . -list /Users UniqueID | awk -v n=$id_num '$2==n{exit 1}' || { print -u2 "UID $id_num taken"; exit 1; }
  dscl . -create /Users/$svc UniqueID $id_num
  dscl . -create /Users/$svc PrimaryGroupID $id_num
  dscl . -create /Users/$svc UserShell /usr/bin/false
  dscl . -create /Users/$svc NFSHomeDirectory $home
  dscl . -create /Users/$svc RealName "op-remote service"
  dscl . -create /Users/$svc Password '*'
  dscl . -create /Users/$svc IsHidden 1
fi

# 2. Home: only _opremote reads it. Group staff (Hermes's group) may pass through to
#    run/, where the 0660 socket lives, and nothing else.
install -d -o $svc -g staff -m 0710 $home
install -d -o $svc -g staff -m 0750 $home/run
install -d -o $svc -g $svc  -m 0700 $home/.config

# 3. Root-owned code. op-remote comes from the npm registry, checked against the
#    registry's sha512, not from nvm (which Hermes can write to).
install -d -o root -g wheel -m 0755 $opt $opt/bin $opt/lib
tmp=$(mktemp -d)
/usr/bin/python3 -I - "$tmp" <<'PY'
import base64, hashlib, json, sys, tarfile, urllib.request
tmp = sys.argv[1]
meta = json.load(urllib.request.urlopen("https://registry.npmjs.org/@wyattjoh/op-remote/latest"))
data = urllib.request.urlopen(meta["dist"]["tarball"]).read()
algo, want = meta["dist"]["integrity"].split("-", 1)
assert algo == "sha512" and base64.b64encode(hashlib.sha512(data).digest()).decode() == want, "integrity mismatch"
open(f"{tmp}/pkg.tgz", "wb").write(data)
with tarfile.open(f"{tmp}/pkg.tgz") as t:
    open(f"{tmp}/cli.js", "wb").write(t.extractfile("package/dist/cli.js").read())
print("op-remote", meta["version"], "verified against the registry")
PY
/usr/bin/python3 -I $stage/patch.py $tmp/cli.js $opt/lib/cli.js
chown root:wheel $opt/lib/cli.js; chmod 0644 $opt/lib/cli.js

# Binaries: copy, then require the expected Developer ID team.
copy_signed() {  # src dst team
  install -o root -g wheel -m 0755 "$1" "$2"
  codesign --verify --strict "$2"
  # Capture first: `codesign | grep -q` fails under pipefail when grep exits early.
  local info; info=$(codesign -dv "$2" 2>&1)
  [[ "$info" == *"TeamIdentifier=$3"* ]] || { print -u2 "$2: wrong signer"; exit 1; }
}
copy_signed /usr/local/bin/op $opt/bin/op 2BUA8C4S2C                  # AgileBits (1Password)
copy_signed "$(ls /Users/$hermes_user/.nvm/versions/node/*/lib/node_modules/bun/bin/bun.exe | head -1)" \
  $opt/bin/bun 7FRXF46ZSN                                              # Bun

for f in serve.sh signin.sh op-remote; do install -o root -g wheel -m 0755 $stage/$f $opt/$f; done
for f in telegram.env gen-secrets.py; do install -o root -g wheel -m 0644 $stage/$f $opt/$f; done
ln -sf $opt/op-remote $opt/bin/op-remote
rm -rf $tmp

# 4. Hermes may start serve.sh as _opremote, and nothing else.
rule=/etc/sudoers.d/op-remote
print "$hermes_user ALL=($svc) NOPASSWD: $opt/serve.sh" > $rule.tmp
chmod 0440 $rule.tmp
visudo -cf $rule.tmp >/dev/null && mv $rule.tmp $rule

print "Isolation in place."
