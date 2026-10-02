#!/usr/bin/env bash
#
# Make every file WhatsApp has already downloaded visible to the rest of the
# phone (Files, Moon+ Reader, the gallery), over adb.
#
# Idempotent: it only ever removes WhatsApp's ".nomedia" markers from the five
# "Private" media folders and asks the media indexer to rescan them. Files are
# never moved or renamed, so WhatsApp's own references to them stay valid.
#
# See README.md for why the files were hidden and why this is the safe fix.

set -euo pipefail

say() { printf '  %s\n' "$*"; }
die() { printf '\n  \033[31m✗\033[0m  %s\n\n' "$*" >&2; exit 1; }

media='/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media'
folders=(
	'WhatsApp Animated Gifs'
	'WhatsApp Audio'
	'WhatsApp Documents'
	'WhatsApp Images'
	'WhatsApp Video'
)

###############################################################################
# PREFLIGHT
###############################################################################

command -v adb >/dev/null 2>&1 || die "adb missing — brew install --cask android-platform-tools"

devices="$(adb devices | grep -cE '\sdevice$' || true)"
[ "$devices" -eq 1 ] || die "need exactly one adb device, found $devices (adb devices)"

adb shell "[ -d '$media' ]" \
	|| die "WhatsApp media folder not found — is WhatsApp installed and has it downloaded anything?"

###############################################################################
# UNHIDE: drop the marker, then rescan so the indexer reclassifies the files
###############################################################################

for f in "${folders[@]}"; do
	dir="$media/$f/Private"
	adb shell "[ -d '$dir' ]" || { say "no Private folder under '$f' — skipping"; continue; }

	if adb shell "[ -f '$dir/.nomedia' ]"; then
		adb shell "rm -f '$dir/.nomedia'"
		say "removed marker: $f/Private/.nomedia"
	else
		say "already unhidden: $f/Private"
	fi

	# MediaProvider indexes files under a .nomedia folder with media_type=0
	# ("none"), which every gallery-style app filters out. Removing the marker
	# alone does not fix existing rows; a rescan of the folder does.
	adb shell "content call --uri content://media/external/file \
		--method scan_file --arg '$dir'" >/dev/null 2>&1 \
		|| die "media rescan failed for '$dir'"
done

###############################################################################
# VERIFY: count indexed rows against files on disk, per folder
###############################################################################

sleep 5
say ""
say "indexed / on disk"
failed=0
for f in "${folders[@]}"; do
	dir="$media/$f/Private"
	adb shell "[ -d '$dir' ]" || continue
	disk="$(adb shell "ls -1 '$dir' | wc -l" | tr -d '\r ')"
	indexed="$(adb shell "content query --uri content://media/external/file \
		--projection _id \
		--where \"_data LIKE '%/$f/Private/%' AND media_type != 0\" | grep -c Row" \
		| tr -d '\r ')"
	say "$(printf '%5s / %-5s  %s' "$indexed" "$disk" "$f")"
	# A handful of files with no recognised type (odd extensions, zero bytes)
	# legitimately stay at media_type=0. Anything bigger means the scan did not
	# take.
	[ $((disk - indexed)) -le 5 ] || failed=1
done

[ "$failed" -eq 0 ] \
	|| die "some folders are still mostly unindexed — check the counts above and re-run"

printf '\n  \033[32m✓\033[0m  WhatsApp media is visible to other apps.\n\n'
