#!/usr/bin/env bash
#
# Make Kagi the default search engine in Firefox for Android, over adb.
#
# Idempotent: re-running edits the existing Kagi engine rather than adding a
# second one, and refreshes the session token at the same time.
#
# See README.md for why this is UI automation rather than a settings write, and
# for the Gboard traps the helpers work around.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ui="python3 $here/lib/ui.py"
typekeys="python3 $here/lib/type_keys.py"
fenix="org.mozilla.firefox"
receiver="$fenix/org.mozilla.fenix.IntentReceiverActivity"

say() { printf '  %s\n' "$*"; }
die() { printf '\n  \033[31m✗\033[0m  %s\n\n' "$*" >&2; exit 1; }

###############################################################################
# HELPERS
###############################################################################

# Tap whatever matches a ui.py selector. Never a bare coordinate: a layout shift
# should fail loudly here rather than tap something else and carry on.
tap() {
	local coords
	coords="$($ui wait "$@")" || die "element not on screen: $*"
	# shellcheck disable=SC2086
	adb shell input tap $coords
}

repeat_key() {
	local key="$1" n="$2" keys=""
	[ "$n" -le 0 ] && return 0
	for _ in $(seq 1 "$n"); do keys="$keys $key"; done
	# shellcheck disable=SC2086
	adb shell input keyevent $keys
}

clear_field() {
	adb shell input keyevent KEYCODE_MOVE_END
	repeat_key KEYCODE_DEL 200
}

# Put the caret at character offset $1 from the start of the focused field.
seek() {
	adb shell input keyevent KEYCODE_MOVE_HOME
	repeat_key KEYCODE_DPAD_RIGHT "$1"
}

###############################################################################
# PREFLIGHT
###############################################################################

command -v adb >/dev/null 2>&1 || die "adb missing — brew install --cask android-platform-tools"
command -v python3 >/dev/null 2>&1 || die "python3 missing"

devices="$(adb devices | grep -cE '\sdevice$' || true)"
[ "$devices" -eq 1 ] || die "need exactly one adb device, found $devices (adb devices)"

adb shell input keyevent KEYCODE_WAKEUP
adb shell dumpsys trust | grep -q 'deviceLocked=0' \
	|| die "phone is locked — unlock it and re-run"

adb shell pm list packages | grep -q "$fenix" \
	|| die "Firefox ($fenix) is not installed on the device"

# The screen blanking mid-run breaks every subsequent tap, and the failure looks
# like a stuck notification shade rather than a timeout. Hold it awake, restore
# on the way out however we exit.
original_timeout="$(adb shell settings get system screen_off_timeout | tr -d '\r')"
restore_timeout() {
	[ -n "${original_timeout:-}" ] && [ "$original_timeout" != "null" ] \
		&& adb shell settings put system screen_off_timeout "$original_timeout" || true
}
trap restore_timeout EXIT
adb shell settings put system screen_off_timeout 600000

screen="$(adb shell wm size | tail -1 | tr -d '\r')"
screen="${screen##*: }"
width="${screen%x*}"
height="${screen#*x}"

###############################################################################
# TOKEN: copy the session URL device-side, so it never touches this machine
###############################################################################

say "Fetching the Kagi session link…"
adb shell am start -a android.intent.action.VIEW \
	-d 'https://kagi.com/settings?p=user_details' -n "$receiver" >/dev/null

found=""
for _ in $(seq 1 10); do
	if $ui find --text 'Session Link' >/dev/null 2>&1; then found=1; break; fi
	if $ui find --contains 'Sign In - Kagi' >/dev/null 2>&1; then
		die "Firefox on the phone is not signed in to Kagi — sign in, then re-run"
	fi
	adb shell input swipe $((width / 2)) $((height * 3 / 4)) $((width / 2)) $((height / 4)) 200
done
[ -n "$found" ] || die "never reached the Session Link section of Kagi's settings"

# Kagi renders a ready-made "https://kagi.com/search?token=…&q=%s" next to this
# button, already in search-engine form.
tap --text 'Copy to Clipboard'

###############################################################################
# ENGINE: add it, or edit the one that is already there
###############################################################################

say "Opening Firefox search settings…"
adb shell am start -a android.intent.action.VIEW \
	-d 'fenix://settings_search_engine' -n "$receiver" >/dev/null
tap --text 'Default search engine'

if $ui find --text 'Kagi' >/dev/null 2>&1; then
	say "Kagi engine already exists — refreshing it…"
	tap --id overflow_menu --row-of-text 'Kagi'
	tap --text 'Edit'
else
	say "Adding a Kagi engine…"
	tap --text 'Add search engine'
	tap --id edit_engine_name
	$typekeys 'Kagi'
fi

# Paste, never type. KEYCODE_PASTE is the only input path Gboard leaves alone.
tap --id edit_search_string
clear_field
adb shell input keyevent KEYCODE_PASTE
case "$($ui text --id edit_search_string)" in
	https://kagi.com/search\?token=*\&q=%s) ;;
	*) die "clipboard did not hold a Kagi session URL — did the copy button fire?" ;;
esac

# Same token, different endpoint. Splice "/search" into "/api/autosuggest":
# "https://kagi.com/" is 17 characters, so "search" occupies offsets 17-22.
tap --id edit_suggest_string
clear_field
adb shell input keyevent KEYCODE_PASTE
seek 23
repeat_key KEYCODE_DEL 6
# The leading "x" on each segment is a throwaway: Gboard capitalises the first
# letter after a "/", so it eats the guard instead of the real character.
$typekeys 'xapi/xautosuggest'
seek 23 && adb shell input keyevent KEYCODE_DEL
seek 18 && adb shell input keyevent KEYCODE_DEL
case "$($ui text --id edit_suggest_string)" in
	https://kagi.com/api/autosuggest\?token=*\&q=%s) ;;
	*) die "suggestion URL did not splice cleanly — open the engine and check it by hand" ;;
esac

adb shell input keyevent KEYCODE_ESCAPE   # drop the keyboard so Save is reachable
tap --id save_button
tap --text 'Kagi'                         # first match is the normal-browsing radio

###############################################################################
# VERIFY: prove it, rather than trusting that the taps landed
###############################################################################

# A private tab has its own cookie jar and is not signed in to Kagi, so results
# here prove the token authenticates on its own.
say "Verifying with a search in a private tab…"
adb shell am start -a android.intent.action.VIEW -d 'about:blank' \
	--ez private_browsing_mode true -n "$receiver" >/dev/null
tap --id ADDRESSBAR_URL_BOX
clear_field
$typekeys 'kagi default check'
adb shell input keyevent KEYCODE_ENTER

$ui wait --contains '- Kagi Search' --timeout 25 >/dev/null \
	|| die "the search did not land on Kagi — open Settings → Search and check the engine"

printf '\n  \033[32m✓\033[0m  Kagi is the default search engine, authenticating by token.\n\n'
