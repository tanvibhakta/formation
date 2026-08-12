#!/usr/bin/env bash
# Open ONE new Ghostty tab at the end of the tab bar and run a command in it.
#
#   open-session-tab.sh "cd '/path/to/cwd' && claude --resume <uuid>"
#
# Call once per session, in left-to-right target order. Two things make the order
# come out right by construction:
#   * Cmd+9 (last_tab) jumps to the end first, because Ghostty's
#     window-new-tab-position defaults to `current` -- a new tab is inserted after
#     the ACTIVE tab, not at the end.
#   * Cmd+T then lands the new tab at the end.
#
# Verification is by PROCESS, not by the accessibility API. Ghostty drops its AX
# window handle constantly -- reliably right after Cmd+T -- so any guard built on
# `count of windows` fails exactly when it is needed. Each tab is one login shell
# child of the Ghostty process, so "did a tab open?" is answerable from ps alone.
# That matters because if Cmd+T silently failed, the keystrokes would land in
# whatever tab still has focus, which is usually the agent driving this script.

set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $0 '<command to run in the new tab>'" >&2; exit 2; }
CMD="$1"

# The main Ghostty process is the one whose args are exactly the binary path.
# Note: pgrep -f does not reliably match it; ps does.
GPID=""
while read -r pid rest; do
  case "$rest" in
    */Ghostty.app/Contents/MacOS/ghostty) GPID="$pid"; break ;;
  esac
done < <(ps -Ao pid=,args=)
[ -n "$GPID" ] || { echo "Ghostty is not running" >&2; exit 1; }

osa() { osascript -e "tell application \"System Events\" to tell application process \"ghostty\" to $1"; }

osa 'set frontmost to true' >/dev/null 2>&1
sleep 0.4

# jump to the last tab so the new one is appended rather than inserted mid-bar
osa 'key code 25 using command down' >/dev/null 2>&1   # Cmd+9 = last_tab
sleep 0.4

before=$(pgrep -P "$GPID" | sort)

osa 'keystroke "t" using command down' >/dev/null 2>&1

# wait for the new tab's shell to appear
new=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.3
  after=$(pgrep -P "$GPID" | sort)
  new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
  [ -n "$new" ] && break
done

count=$(printf '%s\n' "$new" | grep -c '[0-9]')
if [ "$count" -ne 1 ]; then
  echo "ABORT: expected exactly 1 new tab shell, saw ${count}. Not typing." >&2
  exit 1
fi

# Cmd+T focuses the tab it creates, and we just proved it was created.
osa 'keystroke "u" using control down' >/dev/null 2>&1   # clear any stray input
sleep 0.2
esc=${CMD//\\/\\\\}     # escape backslashes, then quotes, for the AppleScript string
esc=${esc//\"/\\\"}
osascript -e "tell application \"System Events\" to tell application process \"ghostty\" to keystroke \"${esc}\"" >/dev/null 2>&1
sleep 0.3
osa 'key code 36' >/dev/null 2>&1                        # Return

echo "opened tab (shell pid $(printf '%s' "$new" | tr -d '[:space:]')) running: ${CMD}"
