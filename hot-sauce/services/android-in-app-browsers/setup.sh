#!/usr/bin/env bash

###############################################################################
# ANDROID: STOP APPS OPENING LINKS IN THEIR OWN BROWSER
#
# Run with the phone plugged in and USB debugging on. Handles the one part adb
# can do (disable Chrome), checks the default browser, then prints the per-app
# toggles that can only be flipped by hand. See README.md for why.
#
# Safe to run repeatedly — every step checks before it acts.
###############################################################################

set -e

print_success() { printf "  [✓] %s\n" "$1"; }
print_warning() { printf "  [!] %s\n" "$1"; }
print_error()   { printf "  [✗] %s\n" "$1"; }

BROWSER=org.mozilla.firefox

echo ""
echo "  ── Device ──"
if ! adb get-state &>/dev/null; then
    print_error "No adb device. Plug in the phone and accept the USB debugging prompt."
    exit 1
fi
print_success "$(adb shell getprop ro.product.model | tr -d '\r') connected"

echo ""
echo "  ── Default browser ──"
holder=$(adb shell cmd role get-role-holders android.app.role.BROWSER | tr -d '\r')
if [ "$holder" = "$BROWSER" ]; then
    print_success "Default browser is $BROWSER"
else
    print_warning "Default browser is '$holder'. Set Firefox in Settings → Apps → Default apps → Browser app, then re-run."
fi

echo ""
echo "  ── Chrome ──"
# Apps that hard-code Chrome as their Custom Tabs provider fall through to the
# default browser once Chrome is gone. The Google app's "Open web pages in the
# app" also needs Chrome, so this switches that off too.
if adb shell pm list packages -d | tr -d '\r' | grep -qx 'package:com.android.chrome'; then
    print_success "Chrome already disabled"
else
    adb shell pm disable-user --user 0 com.android.chrome >/dev/null
    adb shell pm list packages -d | tr -d '\r' | grep -qx 'package:com.android.chrome' \
        && print_success "Chrome disabled" \
        || { print_error "Chrome still enabled"; exit 1; }
fi

providers=$(adb shell cmd package query-services -a android.support.customtabs.action.CustomTabsService \
    | tr -d '\r' | grep -o 'packageName=[^ ]*' | sort -u | cut -d= -f2 | tr '\n' ' ')
print_success "Custom Tabs providers left: ${providers:-none}"

echo ""
echo "  ── Flip these by hand (README.md has the details) ──"
cat <<'EOF'
  Slack      You → Preferences → Device & troubleshooting → Open web pages in app: OFF
  Telegram   Settings → Chat Settings → In-App Browser (tap the label, not the switch)
             → Enable In-App Browser: OFF, Windowed Mode: OFF
  Inoreader  Drawer → Settings → Miscellaneous → Browser: External
  Discord    Avatar → Settings → Web Browser: External Browser
  Raindrop   Gear → Open in browser: System default
  Gmail      Settings → General settings → Open web links in Gmail: OFF
  YouTube    (ReVanced) Settings → ReVanced → Miscellaneous → Open links in browser: ON
  Reddit, X, Beeper, Mastodon, Facebook: not done yet — see README.md
EOF
echo ""
