#!/usr/bin/env bash

###############################################################################
# LET THE ALWAYS-ON MAC SSH INTO THIS LAPTOP
#
# Run on the laptop. Gives the Hermes gateway (on the always-on Mac) a shell
# here, and nothing else:
#   - a dedicated, passphrase-less key generated on the always-on Mac, so
#     Hermes can use it non-interactively without touching its other keys
#   - authorized only from the always-on Mac's fixed IP, with forwarding off
#   - sshd: keys only (no passwords), only this user
#   - `ssh big-macbook` set up on the always-on Mac
#
# Safe to run repeatedly. Every step checks before it acts.
###############################################################################

set -e

REMOTE="${1:-Tanvis-MacBook-Pro.local}"   # the always-on Mac
REMOTE_IP="192.168.0.107"                 # its static IP; see services/pihole
KEY_NAME="id_ed25519_big_macbook"
HOST_ALIAS="big-macbook"
LAPTOP_HOST="$(scutil --get LocalHostName).local"
SSHD_DROPIN="/etc/ssh/sshd_config.d/050-hot-sauce.conf"

if ! type print_success &>/dev/null; then
    print_success() { printf "  [✓] $1\n"; }
    print_warning() { printf "  [!] $1\n"; }
    print_error() { printf "  [✗] $1\n"; }
fi

# Run as root: sudo when there's a terminal, else the macOS password dialog.
as_root() {
    if [ -t 0 ]; then
        sudo /bin/bash -c "$1"
    else
        local escaped=${1//\\/\\\\}
        escaped=${escaped//\"/\\\"}
        osascript -e "do shell script \"$escaped\" with administrator privileges"
    fi
}

###############################################################################
# KEY ON THE ALWAYS-ON MAC
###############################################################################
pubkey="$(ssh -o ConnectTimeout=8 "$REMOTE" "
    [ -f ~/.ssh/$KEY_NAME ] || ssh-keygen -q -t ed25519 -N '' -C 'hermes@always-on -> $HOST_ALIAS' -f ~/.ssh/$KEY_NAME
    cat ~/.ssh/$KEY_NAME.pub")"
print_success "Key ~/.ssh/$KEY_NAME on $REMOTE"

###############################################################################
# AUTHORIZE IT HERE
###############################################################################
# from= pins the key to the always-on Mac. If the private key ever leaked,
# it would not work from any other address.
entry="from=\"$REMOTE_IP\",no-agent-forwarding,no-port-forwarding,no-X11-forwarding $pubkey"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
key_body="$(echo "$pubkey" | awk '{print $2}')"
if grep -qF "$key_body" ~/.ssh/authorized_keys; then
    print_success "Key already in ~/.ssh/authorized_keys"
else
    echo "$entry" >> ~/.ssh/authorized_keys
    print_success "Key added to ~/.ssh/authorized_keys (from $REMOTE_IP only)"
fi

###############################################################################
# SSHD: KEYS ONLY, THIS USER ONLY, AND TURN REMOTE LOGIN ON
###############################################################################
# sshd keeps the FIRST value it reads for each option, and Includes are read
# alphabetically, so 050- wins over macOS's 100-macos.conf.
dropin="# Managed by hot-sauce/services/laptop-ssh/setup.sh
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $USER"

need_dropin=true
[ "$(cat "$SSHD_DROPIN" 2>/dev/null)" = "$dropin" ] && need_dropin=false
need_sshd=true
nc -z -G 2 127.0.0.1 22 2>/dev/null && need_sshd=false

if $need_dropin || $need_sshd; then
    tmp="$(mktemp)"; printf '%s\n' "$dropin" > "$tmp"
    # ssh-keygen -A: host keys don't exist until Remote Login has run once,
    # and `sshd -t` refuses to validate without them.
    cmd="install -m 644 -o root -g wheel '$tmp' '$SSHD_DROPIN' && /usr/bin/ssh-keygen -A && /usr/sbin/sshd -t"
    # The launchd route rather than `systemsetup -setremotelogin on`, which
    # needs Full Disk Access granted to the terminal on recent macOS.
    cmd="$cmd && launchctl enable system/com.openssh.sshd && (launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true)"
    as_root "$cmd"
    rm -f "$tmp"
fi

if [ "$(cat "$SSHD_DROPIN" 2>/dev/null)" = "$dropin" ]; then
    print_success "sshd: keys only, AllowUsers $USER ($SSHD_DROPIN)"
else
    print_error "sshd drop-in not written"; exit 1
fi
for _ in 1 2 3 4 5; do nc -z -G 2 127.0.0.1 22 2>/dev/null && break; sleep 1; done
if nc -z -G 2 127.0.0.1 22 2>/dev/null; then
    print_success "Remote Login on"
else
    print_error "sshd is not listening on port 22"; exit 1
fi

###############################################################################
# `ssh big-macbook` ON THE ALWAYS-ON MAC
###############################################################################
ssh "$REMOTE" "grep -q '^Host $HOST_ALIAS\$' ~/.ssh/config 2>/dev/null || cat >> ~/.ssh/config <<EOF

Host $HOST_ALIAS
    HostName $LAPTOP_HOST
    User $USER
    IdentityFile ~/.ssh/$KEY_NAME
    IdentitiesOnly yes
EOF"
print_success "ssh $HOST_ALIAS configured on $REMOTE -> $LAPTOP_HOST"

###############################################################################
# VERIFY FROM THE ALWAYS-ON MAC
###############################################################################
# Compare stdout only: the first connection also prints a "Permanently
# added ... to the list of known hosts" warning on stderr.
errfile="$(mktemp)"
got="$(ssh "$REMOTE" "ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new $HOST_ALIAS hostname" 2>"$errfile")" || true
if [ "$got" = "$(hostname)" ]; then
    print_success "Verified: $REMOTE can run commands here as $USER"
    rm -f "$errfile"
else
    print_error "ssh $HOST_ALIAS from $REMOTE failed: ${got:-$(cat "$errfile")}"; rm -f "$errfile"; exit 1
fi
