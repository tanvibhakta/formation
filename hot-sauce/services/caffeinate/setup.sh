#!/usr/bin/env bash

###############################################################################
# STAY AWAKE ON AC POWER + CAFFEINE DOSE ALFRED WORKFLOW
#
# 1. pmset -c sleep 0: the Mac never idle-sleeps while plugged in, and keeps
#    its normal battery behaviour when unplugged. This is the macOS setting
#    itself, so it needs no app or process running.
# 2. Installs the Caffeine Dose Alfred workflow (`caff`, `cfs 2h`) for
#    keeping the Mac awake on battery, which pmset leaves alone.
#
# Safe to run repeatedly. Every step checks before it acts.
###############################################################################

set -e

WORKFLOW_BUNDLE_ID="com.github.vanstrouble.alfred.caffeinedose"
WORKFLOW_REPO="vanstrouble/caffeine-dose-alfred-workflow"

if ! type print_success &>/dev/null; then
    print_success() { printf "  [✓] $1\n"; }
    print_warning() { printf "  [!] $1\n"; }
    print_error() { printf "  [✗] $1\n"; }
fi

###############################################################################
# AC POWER: NEVER IDLE-SLEEP
###############################################################################
ac_sleep() {
    pmset -g custom | awk '/^AC Power:/{ac=1; next} /^[A-Za-z].*:$/{ac=0} ac && $1=="sleep"{print $2}'
}

if [ "$(ac_sleep)" = "0" ]; then
    print_success "AC power: system sleep already disabled"
else
    if [ -t 0 ]; then
        sudo pmset -c sleep 0
    else
        # No terminal for sudo to prompt in (e.g. run from an agent or Alfred):
        # fall back to the macOS admin-password dialog.
        osascript -e 'do shell script "/usr/bin/pmset -c sleep 0" with administrator privileges'
    fi
    if [ "$(ac_sleep)" = "0" ]; then
        print_success "AC power: system sleep disabled"
    else
        print_error "AC power: sleep is still $(ac_sleep) after pmset"
        exit 1
    fi
fi

###############################################################################
# CAFFEINE DOSE WORKFLOW
###############################################################################
sync_folder="$(defaults read com.runningwithcrayons.Alfred-Preferences syncfolder 2>/dev/null || true)"
sync_folder="${sync_folder/#\~/$HOME}"
prefs="${sync_folder:-$HOME/Library/Application Support/Alfred}/Alfred.alfredpreferences"

installed=false
for plist in "$prefs"/workflows/*/info.plist; do
    [ -f "$plist" ] || continue
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :bundleid' "$plist" 2>/dev/null)" = "$WORKFLOW_BUNDLE_ID" ]; then
        installed=true
        break
    fi
done

if $installed; then
    print_success "Caffeine Dose workflow already installed"
else
    url="$(curl -fsSL "https://api.github.com/repos/$WORKFLOW_REPO/releases/latest" |
        awk -F'"' '/browser_download_url/ && /\.alfredworkflow"/{print $4; exit}')"
    if [ -z "$url" ]; then
        print_error "Could not find a .alfredworkflow in the latest $WORKFLOW_REPO release"
        exit 1
    fi
    dest="$HOME/Downloads/$(basename "$url")"
    curl -fsSL -o "$dest" "$url"
    open "$dest"
    print_warning "Click Import in the Alfred dialog to finish installing $(basename "$url")"
fi
