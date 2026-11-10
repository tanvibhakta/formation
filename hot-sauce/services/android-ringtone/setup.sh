#!/usr/bin/env bash

###############################################################################
# ANDROID: TURN A YOUTUBE CLIP INTO THE PHONE RINGTONE
#
# Usage:
#   ./setup.sh <adb-serial> <youtube-url> <start-seconds> <length-seconds> "<title>"
#
# Example:
#   ./setup.sh 192.168.1.3:39963 "https://www.youtube.com/watch?v=T2ou5-ai-Uk" \
#       9 40 "Mungaru Maleye Flute"
#
# The serial is required on purpose: more than one phone is usually attached to
# this laptop, and this must never land on the wrong one. See README.md.
#
# Safe to run repeatedly — the same title overwrites the same file on the phone.
###############################################################################

set -euo pipefail

print_success() { printf "  [✓] %s\n" "$1"; }
print_error()   { printf "  [✗] %s\n" "$1"; }

if [ "$#" -ne 5 ]; then
    sed -n '3,17p' "$0"
    exit 1
fi

SERIAL=$1 URL=$2 START=$3 LENGTH=$4 TITLE=$5
SLUG=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
REMOTE="/storage/emulated/0/Ringtones/$SLUG.mp3"
WORK=~/Code/llm-workspace/$(date +%Y%m%d)-ringtone/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$WORK/download"

phone() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }

echo ""
echo "  ── Device ──"
print_success "$(phone getprop ro.product.model) at $SERIAL"

echo ""
echo "  ── Clip ──"
yt-dlp --no-playlist -f bestaudio -o "$WORK/download/source.%(ext)s" "$URL" >"$WORK/yt-dlp.log" 2>&1 \
    || { print_error "yt-dlp failed; a 403 usually means it is out of date. Log: $WORK/yt-dlp.log"; exit 1; }
SOURCE=$(ls "$WORK"/download/source.*)
FADE_AT=$(awk "BEGIN { print $LENGTH - 2 }")
ffmpeg -hide_banner -loglevel error -y -ss "$START" -t "$LENGTH" -i "$SOURCE" \
    -af "afade=t=in:d=0.05,afade=t=out:st=$FADE_AT:d=2,loudnorm=I=-14:TP=-1" \
    -ar 44100 -c:a libmp3lame -q:a 2 -metadata title="$TITLE" "$WORK/$SLUG.mp3"
print_success "Cut ${LENGTH}s from ${START}s: $WORK/$SLUG.mp3"

echo ""
echo "  ── Previous ringtone (to undo, see README.md) ──"
phone settings list system | { grep -E '^ringtone(_sound_slot_[12])?=' || true; } | tee "$WORK/previous-ringtone.txt"

echo ""
echo "  ── Install ──"
phone mkdir -p /storage/emulated/0/Ringtones
adb -s "$SERIAL" push "$WORK/$SLUG.mp3" "$REMOTE" >/dev/null
phone am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$REMOTE" >/dev/null

MEDIA_ID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    MEDIA_ID=$(phone content query --uri content://media/external_primary/audio/media \
        --projection _id --where "\"_data='$REMOTE'\"" | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | head -n 1)
    [ -n "$MEDIA_ID" ] && break
    sleep 1
done
if [ -z "$MEDIA_ID" ]; then
    print_error "The media scanner never indexed $REMOTE"
    exit 1
fi
phone content update --uri "content://media/external_primary/audio/media/$MEDIA_ID" \
    --bind is_ringtone:i:1 --bind is_music:i:0 >/dev/null
print_success "Indexed as media id $MEDIA_ID"

echo ""
echo "  ── Set as ringtone (both SIM slots) ──"
URI="content://0@media/external_primary/audio/media/$MEDIA_ID"
for key in ringtone ringtone_sound_slot_1 ringtone_sound_slot_2; do
    phone settings put system "$key" "$URI"
    actual=$(phone settings get system "$key")
    if [ "$actual" = "$URI" ]; then
        print_success "$key"
    else
        print_error "$key is '$actual', expected '$URI'"
        exit 1
    fi
done
