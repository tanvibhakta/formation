#!/usr/bin/env bash

###############################################################################
# TWITTER (PIKO) SETUP
#
# Patches the official X Android app with piko (github.com/crimera/piko):
# ads removed, and the old Twitter name + bird icon restored. Installs it on
# the phone connected over adb.
#
#   ./setup.sh <path-to-X.apkm>
#
# The X bundle has to come from APKMirror by hand — APKMirror 403s scripted
# downloads. Run with no argument first and the script prints the exact
# version to fetch.
#
# Safe to run repeatedly — every step checks before it acts.
###############################################################################

set -euo pipefail

STATE_DIR="$HOME/.config/twitter-piko"
KEYSTORE="$STATE_DIR/twitter-piko.keystore"
WORK_DIR="$STATE_DIR/work"
PACKAGE="com.twitter.android"
JAVA="/opt/homebrew/opt/openjdk/bin/java"

print_success() { printf "  [✓] %s\n" "$1"; }
print_warning() { printf "  [!] %s\n" "$1"; }
print_error() { printf "  [✗] %s\n" "$1"; }
ask() {
    local reply
    echo -n "  [?] $1 [y/N] "
    read -r reply </dev/tty
    case "$reply" in Y*|y*) return 0 ;; *) return 1 ;; esac
}

mkdir -p "$WORK_DIR"

###############################################################################
# TOOLS
###############################################################################

# Morphe needs Java 21+. Called by full path so the shell's default Java
# (pinned to 17 in dotfiles/zshrc) is left alone.
if [ ! -x "$JAVA" ]; then
    brew install openjdk
fi
print_success "Java: $("$JAVA" -version 2>&1 | head -1)"

command -v adb >/dev/null || brew install --cask android-platform-tools
command -v gh >/dev/null || { print_error "gh CLI is required to fetch releases"; exit 1; }
command -v op >/dev/null || { print_error "1Password CLI (op) is required for the signing key"; exit 1; }

# Latest STABLE releases only — piko ships a dev pre-release almost daily.
MORPHE_TAG=$(gh release view -R MorpheApp/morphe-desktop --json tagName -q .tagName)
PIKO_TAG=$(gh release view -R crimera/piko --json tagName -q .tagName)
MORPHE_JAR="$WORK_DIR/morphe-desktop-${MORPHE_TAG#v}-all.jar"
PIKO_MPP="$WORK_DIR/patches-${PIKO_TAG#v}.mpp"

[ -f "$MORPHE_JAR" ] || gh release download "$MORPHE_TAG" -R MorpheApp/morphe-desktop -D "$WORK_DIR"
[ -f "$PIKO_MPP" ] || gh release download "$PIKO_TAG" -R crimera/piko -D "$WORK_DIR"
print_success "Morphe $MORPHE_TAG, piko $PIKO_TAG"

###############################################################################
# SIGNING KEY
###############################################################################

# Android only accepts an update signed with the same key as the installed
# app, so the key is backed up in 1Password and pulled from there at run time.
# Two 1Password accounts share one sign-in URL here, so name the account by UUID.
OP_ACCOUNT_ID="${OP_ACCOUNT_ID:-JPW5BXRIQ5C2HHEMDIYUWTIWTQ}"
OP_VAULT="Private"
OP_ITEM="Twitter piko signing keystore"

if [ ! -f "$KEYSTORE" ]; then
    if op document get "$OP_ITEM" --account "$OP_ACCOUNT_ID" --vault "$OP_VAULT" \
        --out-file "$KEYSTORE" >/dev/null 2>&1; then
        print_success "Signing key restored from 1Password"
    else
        print_warning "No signing key in 1Password — Morphe will create a new one"
    fi
else
    print_success "Signing key: $KEYSTORE"
fi

###############################################################################
# WHICH X VERSION
###############################################################################

# piko supports exactly one X build per release. Read it from the patches
# rather than hard-coding it, so this never goes stale.
SUPPORTED=$("$JAVA" -jar "$MORPHE_JAR" list-patches --patches="$PIKO_MPP" \
    -f "$PACKAGE" -v 2>/dev/null | awk '/Compatible versions:/{getline; gsub(/[ \t]/,""); print; exit}')
print_success "piko $PIKO_TAG supports X $SUPPORTED"

APKM="${1:-}"
if [ -z "$APKM" ] || [ ! -f "$APKM" ]; then
    print_warning "Download the X $SUPPORTED bundle (.apkm) from APKMirror:"
    echo "      https://www.apkmirror.com/apk/x-corp/twitter/x-${SUPPORTED//./-}-release/"
    echo "      then re-run: $0 ~/Downloads/com.twitter.android_${SUPPORTED}-*.apkm"
    exit 1
fi
case "$(basename "$APKM")" in
    *"$SUPPORTED"*) ;;
    *) print_error "$APKM is not X $SUPPORTED"; exit 1 ;;
esac

###############################################################################
# PATCH
###############################################################################

# "Remove Ads" is on by default. "Bring back twitter" (name + bird icon) is
# OFF by default, so it must be enabled by name.
OUT="$WORK_DIR/twitter-piko-$SUPPORTED.apk"
if [ ! -f "$OUT" ]; then
    "$JAVA" -jar "$MORPHE_JAR" patch \
        --patches="$PIKO_MPP" \
        -e "Bring back twitter" \
        --keystore="$KEYSTORE" \
        -o "$OUT" \
        "$APKM"
fi
print_success "Patched: $OUT"

# First run only: back up the key Morphe just generated.
if ! op item get "$OP_ITEM" --account "$OP_ACCOUNT_ID" --vault "$OP_VAULT" >/dev/null 2>&1; then
    op document create "$KEYSTORE" --account "$OP_ACCOUNT_ID" --vault "$OP_VAULT" \
        --title "$OP_ITEM" --file-name twitter-piko.keystore --tags formation,android >/dev/null
    print_success "Signing key backed up to 1Password ($OP_VAULT)"
fi

###############################################################################
# INSTALL
###############################################################################

if ! adb get-state >/dev/null 2>&1; then
    print_error "No phone on adb. Turn on Developer options → USB debugging and plug in."
    exit 1
fi

# A Play Store X is signed by X Corp, so Android refuses our build over it.
# Try the update first; uninstall (which logs you out) only if it refuses.
if ! INSTALL_OUT=$(adb install -r "$OUT" 2>&1); then
    if [[ "$INSTALL_OUT" == *UPDATE_INCOMPATIBLE* ]]; then
        print_warning "The installed X is signed with a different key (probably the Play Store build)."
        ask "Uninstall it? You will be logged out." || exit 1
        adb uninstall "$PACKAGE"
        adb install "$OUT"
    else
        echo "$INSTALL_OUT"
        exit 1
    fi
fi

INSTALLED=$(adb shell dumpsys package "$PACKAGE" | awk -F= '/versionName/{print $2; exit}')
if [ "$INSTALLED" = "$SUPPORTED" ]; then
    print_success "Twitter $INSTALLED installed"
else
    print_error "Expected $SUPPORTED on the phone, found ${INSTALLED:-nothing}"
    exit 1
fi

print_warning "In the Play Store, open X → ⋮ → untick 'Enable auto update', or it will overwrite this."
