# Android ringtone from a YouTube clip

`setup.sh` downloads a video's audio, cuts a clip, pushes it to the phone and
sets it as the ringtone for both SIM slots.

```
./setup.sh <adb-serial> <youtube-url> <start-seconds> <length-seconds> "<title>"
```

To change the cut, re-run with a new start or length and the same title. That
overwrites the same file on the phone.

## Traps

- **Pass the serial every time.** Other phones are often attached over wireless
  debugging, and a bare `adb shell` either fails or hits the wrong one. Run
  `adb devices -l` to find it. The wireless debugging port changes between
  sessions.
- **HTTP 403 from yt-dlp means it is out of date.** Run `brew upgrade yt-dlp`.
  This also upgrades its dependencies and their dependents, including ffmpeg and
  node.
- **Xiaomi HyperOS keeps three settings.** `ringtone` is the standard one, and
  `ringtone_sound_slot_1` and `_2` are per SIM. Setting only `ringtone` can leave
  a SIM on the old tone.

## Undo

Each run prints the previous values and saves them to `previous-ringtone.txt` in
its work folder under `~/Code/llm-workspace/`. Put a value back with:

```
adb -s <serial> shell settings put system <key> '<previous value>'
```
