"""Type a string into the focused Android field using raw key events.

`adb shell input text` routes through the IME. Gboard then "helps": it inserts a
space after punctuation (`kagi.com` -> `kagi. com`), capitalises the first letter
after a `/`, and converts `%s` into a space outright. Every one of those
produces a URL that looks fine at a glance and silently does the wrong thing.

Injecting key codes fixes `%s`, but auto-space and auto-capitalise still apply,
so callers that care about exact text should paste (KEYCODE_PASTE) instead and
keep this for short, punctuation-free strings like an engine name.

Usage: python3 type_keys.py 'Kagi'
"""
import subprocess
import sys

PLAIN = {".": "KEYCODE_PERIOD", "/": "KEYCODE_SLASH", "=": "KEYCODE_EQUALS",
         "-": "KEYCODE_MINUS", ",": "KEYCODE_COMMA", ";": "KEYCODE_SEMICOLON",
         "'": "KEYCODE_APOSTROPHE", "\\": "KEYCODE_BACKSLASH", " ": "KEYCODE_SPACE"}

# char -> the unshifted key whose shifted form produces it (US layout).
SHIFTED = {":": "KEYCODE_SEMICOLON", "?": "KEYCODE_SLASH", "%": "KEYCODE_5",
           "&": "KEYCODE_7", "+": "KEYCODE_EQUALS", "_": "KEYCODE_MINUS",
           "#": "KEYCODE_3", "@": "KEYCODE_2", "!": "KEYCODE_1", "$": "KEYCODE_4",
           "(": "KEYCODE_9", ")": "KEYCODE_0", "~": "KEYCODE_GRAVE", "*": "KEYCODE_8"}


def keycode(ch):
    if ch.isalpha() and ch.isascii():
        return f"KEYCODE_{ch.upper()}", ch.isupper()
    if ch.isdigit():
        return f"KEYCODE_{ch}", False
    if ch in PLAIN:
        return PLAIN[ch], False
    if ch in SHIFTED:
        return SHIFTED[ch], True
    raise SystemExit(f"no key mapping for {ch!r}")


def adb(*args):
    subprocess.run(["adb", "shell", "input", *args], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


batch = []  # consecutive unshifted keys go in one call, to cut adb round-trips
for ch in sys.argv[1]:
    name, shift = keycode(ch)
    if shift:
        if batch:
            adb("keyevent", *batch)
            batch = []
        adb("keycombination", "KEYCODE_SHIFT_LEFT", name)
    else:
        batch.append(name)
if batch:
    adb("keyevent", *batch)
