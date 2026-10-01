#!/usr/bin/env bash
# chrome-mcp-reap.sh — clean up Chrome instances spawned by the chrome-devtools MCP.
#
# The MCP runs with --isolated, so EVERY Claude session that drives Chrome spins up
# its own throwaway browser (user-data-dir=.../puppeteer_dev_chrome_profile-*). Those
# stay open for the life of the session and sometimes linger after it dies. This reaper
# closes them at the right moments.
#
# Keep Chrome on --isolated. A shared-profile flag (--autoConnect, or a persistent
# --userDataDir) collapses every parallel session onto ONE browser, and they then fight
# over tabs — which is the exact failure this reaper's per-session tree walks exist to
# avoid. Authenticated browsing that genuinely needs a signed-in profile goes to the
# firefox-devtools MCP (--autoProfile, one shared profile, inherently serial) instead.
#
# Modes:
#   session  (SessionEnd):   kill THIS session's chrome-devtools-mcp tree + its Chrome.
#   orphans  (SessionStart): kill chrome-devtools-mcp trees whose owning `claude`
#                            process is already gone (force-killed sessions, backlog).
#
# Safety:
#   - Only ever targets chrome-devtools-mcp server processes and the Chrome they
#     launched (puppeteer_dev_chrome_profile user-data-dir). Your real browser — any
#     Chrome without that temp profile — is never touched.
#   - `session` mode only kills trees under the current session's own `claude`, so
#     parallel Claude sessions are unaffected.
#   - Set CHROME_REAP_DRY=1 to log what would be killed without killing anything.
#
# Written for macOS /bin/bash 3.2 (no mapfile / associative arrays).

set -uo pipefail

MODE="${1:-orphans}"
DRY="${CHROME_REAP_DRY:-0}"
LOG="$HOME/.claude/chrome-mcp-reap.log"

# Space-padded list of live claude session PIDs for O(1) membership tests.
CLAUDE_PIDS=" $(pgrep -x claude 2>/dev/null | tr '\n' ' ') "

ts() { date '+%Y-%m-%dT%H:%M:%S'; }

is_claude() {
  case "$CLAUDE_PIDS" in
    *" $1 "*) return 0 ;;
  esac
  [ "$(ps -o comm= -p "$1" 2>/dev/null | xargs 2>/dev/null)" = "claude" ] && return 0
  return 1
}

ppid_of() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; }

# 0 if any ancestor of $1 is a live claude session.
has_claude_ancestor() {
  local pid="$1" guard=0 pp
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    is_claude "$pid" && return 0
    pp="$(ppid_of "$pid")"
    [ -z "$pp" ] && break
    pid="$pp"
    guard=$((guard + 1)); [ "$guard" -gt 40 ] && break
  done
  return 1
}

# 0 if $2 is $1 or any ancestor of $1.
ancestor_is() {
  local pid="$1" target="$2" guard=0 pp
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    [ "$pid" = "$target" ] && return 0
    pp="$(ppid_of "$pid")"
    [ -z "$pp" ] && break
    pid="$pp"
    guard=$((guard + 1)); [ "$guard" -gt 40 ] && break
  done
  return 1
}

# Print a PID and all its descendants, one per line.
collect_tree() {
  echo "$1"
  for k in $(pgrep -P "$1" 2>/dev/null); do
    collect_tree "$k"
  done
}

kill_tree() {
  local root="$1" pids
  pids="$(collect_tree "$root" | sort -un | tr '\n' ' ')"
  [ -z "${pids// /}" ] && return 0
  if [ "$DRY" = "1" ]; then
    echo "[$(ts)] DRY would kill root=$root pids=$pids" >> "$LOG"
    return 0
  fi
  echo $pids | xargs kill -TERM 2>/dev/null
  sleep 1
  echo $pids | xargs kill -KILL 2>/dev/null
  echo "[$(ts)] killed root=$root pids=$pids" >> "$LOG"
}

# Root processes of each chrome-devtools-mcp tree: a matching process whose parent
# is NOT itself a chrome-devtools-mcp process (i.e. the top of the npm/server stack).
CDM_PIDS=" $(pgrep -f 'chrome-devtools-mcp' 2>/dev/null | tr '\n' ' ') "
roots() {
  local p pp
  for p in $CDM_PIDS; do
    [ -z "$p" ] && continue
    pp="$(ppid_of "$p")"
    case "$CDM_PIDS" in
      *" $pp "*) : ;;        # parent is also a CDM process -> not a root
      *) echo "$p" ;;
    esac
  done
}

# Find this session's claude by walking up from this process's own ancestry.
my_session_claude() {
  local pid="$$" guard=0
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    is_claude "$pid" && { echo "$pid"; return 0; }
    pid="$(ppid_of "$pid")"
    guard=$((guard + 1)); [ "$guard" -gt 40 ] && break
  done
  return 1
}

killed=0

case "$MODE" in
  window)
    # Mid-session close: kill ONLY this session's Chrome, keep the MCP server node
    # alive. The chrome-devtools MCP transparently relaunches a fresh browser on the
    # next tool call, so the session keeps working — the window just goes away.
    my_claude="$(my_session_claude)" || exit 0
    [ -z "$my_claude" ] && exit 0
    chrome_pids=""
    for p in $(collect_tree "$my_claude"); do
      case "$(ps -o command= -p "$p" 2>/dev/null)" in
        *puppeteer_dev_chrome_profile*) chrome_pids="$chrome_pids $p" ;;
      esac
    done
    chrome_pids="$(echo $chrome_pids | tr ' ' '\n' | sort -un | tr '\n' ' ')"
    if [ -n "${chrome_pids// /}" ]; then
      if [ "$DRY" = "1" ]; then
        echo "[$(ts)] DRY would close window pids=$chrome_pids" >> "$LOG"
      else
        echo $chrome_pids | xargs kill -TERM 2>/dev/null
        sleep 1
        echo $chrome_pids | xargs kill -KILL 2>/dev/null
        echo "[$(ts)] closed window pids=$chrome_pids" >> "$LOG"
      fi
      killed=1
    fi
    ;;
  session)
    # SessionEnd: tear down this session's whole chrome-devtools-mcp tree (server +
    # watchdog + Chrome). The session is ending, so the server is not needed.
    my_claude="$(my_session_claude)" || exit 0
    [ -z "$my_claude" ] && exit 0
    for r in $(roots); do
      if ancestor_is "$r" "$my_claude"; then
        kill_tree "$r"; killed=$((killed + 1))
      fi
    done
    ;;
  orphans)
    # SessionStart: reap chrome-devtools-mcp trees whose owning claude is already gone
    # (force-killed sessions that never fired SessionEnd, plus any standing backlog).
    for r in $(roots); do
      if ! has_claude_ancestor "$r"; then
        kill_tree "$r"; killed=$((killed + 1))
      fi
    done
    ;;
  *)
    echo "usage: chrome-mcp-reap.sh [window|session|orphans]" >&2
    exit 2
    ;;
esac

if [ "$killed" -gt 0 ]; then
  verb="closed"; [ "$DRY" = "1" ] && verb="would close"
  printf '{"systemMessage":"chrome-mcp-reap[%s]: %s %d Chrome browser(s)","suppressOutput":true}\n' "$MODE" "$verb" "$killed"
fi
exit 0
