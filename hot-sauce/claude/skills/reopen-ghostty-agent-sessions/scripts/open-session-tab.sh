#!/usr/bin/env bash
# Open ONE new Ghostty tab at the end of the tab bar, run a command in it, and
# confirm the command actually started.
#
#   open-session-tab.sh "cd '/path/to/cwd' && claude --resume <uuid>"
#
# Exits 0 only once the command is running. Exits 1 if it never started, after
# leaving no tab behind, so the caller can stop before opening the next session.
#
# Call once per session, in left-to-right target order. Two things make the order
# come out right by construction:
#   * Cmd+9 (last_tab) jumps to the end first, because Ghostty's
#     window-new-tab-position defaults to `current` -- a new tab is inserted after
#     the ACTIVE tab, not at the end.
#   * Cmd+T then lands the new tab at the end.
#
# A failed attempt must not leave a gap in that order, so a tab whose command did
# not start is closed and the retry opens a fresh tab, still at the end. Retyping
# into the same tab would need it to still have focus, which nothing can guarantee.
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

MAX_ATTEMPTS=3
# Resumed sessions appeared within 3s on a real restore; 20s allows for a busy machine.
START_WAIT_SECONDS="${OPEN_TAB_START_WAIT:-20}"

# What to look for in ps: the part after `cd X && `, which carries the session id.
NEEDLE="${CMD##*&& }"

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

# True if a process under the given tab shell has the command in its args.
command_running_under() {
  ps -Ao pid=,ppid=,args= | awk -v root="$1" -v needle="$NEEDLE" '
    { parent[$1] = $2; if (index($0, needle)) match_pid[$1] = 1 }
    END {
      for (m in match_pid)
        for (p = m; p in parent && p != 1; p = parent[p])
          if (p == root) exit_code = 1
      exit !exit_code
    }'
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  osa 'set frontmost to true' >/dev/null 2>&1
  sleep 0.4

  # jump to the last tab so the new one is appended rather than inserted mid-bar
  osa 'key code 25 using command down' >/dev/null 2>&1   # Cmd+9 = last_tab
  sleep 0.4

  before=$(pgrep -P "$GPID" | sort)

  osa 'keystroke "t" using command down' >/dev/null 2>&1

  # wait for the new tab's shell to appear
  new=""
  for _ in $(seq 1 20); do
    sleep 0.3
    after=$(pgrep -P "$GPID" | sort)
    new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
    [ -n "$new" ] && break
  done

  count=$(printf '%s\n' "$new" | grep -c '[0-9]')
  if [ "$count" -eq 0 ]; then
    echo "attempt ${attempt}: no new tab appeared. Nothing typed." >&2
    continue
  fi
  if [ "$count" -ne 1 ]; then
    # Something else is opening tabs too, so we cannot tell which one is ours.
    echo "ABORT: expected exactly 1 new tab shell, saw ${count}. Not typing." >&2
    exit 1
  fi
  new=$(printf '%s' "$new" | tr -d '[:space:]')

  # Cmd+T focuses the tab it creates, and we just proved it was created.
  osa 'keystroke "u" using control down' >/dev/null 2>&1   # clear any stray input
  sleep 0.2
  esc=${CMD//\\/\\\\}     # escape backslashes, then quotes, for the AppleScript string
  esc=${esc//\"/\\\"}
  osascript -e "tell application \"System Events\" to tell application process \"ghostty\" to keystroke \"${esc}\"" >/dev/null 2>&1
  sleep 0.3
  osa 'key code 36' >/dev/null 2>&1                        # Return

  # A tab opening does not prove the command ran: keystrokes can be dropped, and
  # the shell then sits idle at a prompt.
  for _ in $(seq 1 "$START_WAIT_SECONDS"); do
    if command_running_under "$new"; then
      echo "started in tab (shell pid ${new}): ${CMD}"
      exit 0
    fi
    sleep 1
  done

  echo "attempt ${attempt}: not running after ${START_WAIT_SECONDS}s. Closing tab ${new}." >&2
  command_running_under "$new" || kill "$new"
done

echo "FAILED: never started after ${MAX_ATTEMPTS} attempts: ${CMD}" >&2
exit 1
