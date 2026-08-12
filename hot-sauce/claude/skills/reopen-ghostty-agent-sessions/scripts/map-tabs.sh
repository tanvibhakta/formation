#!/usr/bin/env bash
# Map every Ghostty tab to what is running in it, using processes rather than the
# accessibility API. Each tab is one login-shell child of the Ghostty process.
#
#   map-tabs.sh
#
# Prints one line per tab:
#   shell=<pid> self=<yes|no> agent=<command | IDLE>
#
# `self=yes` marks the tab this script is running in. Never close that one.
#
# This is the reliable way to answer "which tabs are idle leftovers and which hold
# live work". Tab titles lie (they revert to the cwd when a command exits) and the
# AX API goes stale, but the process tree does not.

set -uo pipefail

# pgrep -P omits the caller's own ancestor shell, which would silently drop the
# tab you are sitting in from the listing. ps sees everything.
children_of() {
  local target="$1" pid ppid
  while read -r pid ppid; do
    [ "$ppid" = "$target" ] && printf '%s\n' "$pid"
  done < <(ps -Ao pid=,ppid=)
}

GPID=""
while read -r pid rest; do
  case "$rest" in
    */Ghostty.app/Contents/MacOS/ghostty) GPID="$pid"; break ;;
  esac
done < <(ps -Ao pid=,args=)
[ -n "$GPID" ] || { echo "Ghostty is not running" >&2; exit 1; }

# Walk our own ancestry so we can flag the tab we live in.
MYCHAIN=""
p=$$
while [ -n "$p" ] && [ "$p" != "1" ]; do
  MYCHAIN="$MYCHAIN $p"
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done

for lp in $(children_of "$GPID"); do
  agent=""
  for d in $(children_of "$lp"); do
    for dd in $d $(children_of "$d"); do
      a=$(ps -o args= -p "$dd" 2>/dev/null | cut -c1-60)
      case "$a" in
        *claude*|*codex*|*omp*) agent="$a" ;;
      esac
    done
  done
  self=no
  case " $MYCHAIN " in *" $lp "*) self=yes ;; esac
  printf 'shell=%s self=%s agent=%s\n' "$lp" "$self" "${agent:-IDLE}"
done
