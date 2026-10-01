#!/usr/bin/env bash
# List coding-agent sessions that were alive at a cutoff moment, across every
# harness installed on this machine. Output is TSV:
#   harness <TAB> last_write <TAB> session_id <TAB> cwd <TAB> label
#
# Usage:
#   discover-sessions.sh                # cutoff = last boot (system restart case)
#   discover-sessions.sh --within 10    # cutoff = now, look back 10 minutes (close case)
#   discover-sessions.sh --at '2026-08-12 10:45' --window 3
#
# A session counts as "alive at the cutoff" if its transcript was still being
# written within --window minutes before the cutoff. Agents flush on nearly every
# turn, so a live session's file is warm; a session closed an hour ago is not.

set -uo pipefail

WINDOW=5
CUTOFF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --within)  CUTOFF="now"; WINDOW="$2"; shift 2 ;;
    --at)      CUTOFF="$2"; shift 2 ;;
    --window)  WINDOW="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | cut -c3-; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CUTOFF" ]; then
  # kern.boottime is when the machine came back up, i.e. the moment of the crash.
  # Output is "{ sec = 1789559884, usec = 352203 }". Anchor on the leading brace:
  # a leading .* would match greedily through "usec" and yield the microseconds.
  boot_epoch=$(sysctl -n kern.boottime | sed -n 's/^{ *sec = \([0-9]*\).*/\1/p' 2>/dev/null)
  [ -z "$boot_epoch" ] && { echo "could not read boot time" >&2; exit 1; }
  CUT_EPOCH="$boot_epoch"
elif [ "$CUTOFF" = "now" ]; then
  CUT_EPOCH=$(date +%s)
else
  CUT_EPOCH=$(date -j -f '%Y-%m-%d %H:%M' "$CUTOFF" +%s 2>/dev/null) \
    || { echo "bad --at (want 'YYYY-MM-DD HH:MM')" >&2; exit 1; }
fi

LOW=$((CUT_EPOCH - WINDOW * 60))

# mtime in epoch seconds, portable to the BSD stat on macOS
mtime() { stat -f %m "$1" 2>/dev/null; }
iso()   { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null; }

in_window() {
  local m="$1"
  [ -n "$m" ] && [ "$m" -ge "$LOW" ] && [ "$m" -le "$CUT_EPOCH" ]
}

emit() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }

# ---------- Claude Code : ~/.claude/projects/<cwd-slug>/<uuid>.jsonl ----------
if [ -d "$HOME/.claude/projects" ]; then
  while IFS= read -r f; do
    m=$(mtime "$f"); in_window "$m" || continue
    id=$(basename "$f" .jsonl)
    cwd=$(tail -400 "$f" | jq -r 'select(.cwd) | .cwd' 2>/dev/null | tail -1)
    [ -z "$cwd" ] && cwd=$(head -80 "$f" | jq -r 'select(.cwd) | .cwd' 2>/dev/null | head -1)
    label=$(jq -r 'select(.type=="user") | .message.content | select(type=="string")' "$f" 2>/dev/null | head -1 | cut -c1-70)
    emit claude "$(iso "$m")" "$id" "${cwd:-?}" "${label:-?}"
  done < <(find "$HOME/.claude/projects" -name '*.jsonl' -type f 2>/dev/null)
fi

# ---------- Codex : ~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl ----------
if [ -d "$HOME/.codex/sessions" ]; then
  while IFS= read -r f; do
    m=$(mtime "$f"); in_window "$m" || continue
    meta=$(head -1 "$f" 2>/dev/null)
    id=$(printf '%s' "$meta" | jq -r '.payload.session_id // empty' 2>/dev/null)
    cwd=$(printf '%s' "$meta" | jq -r '.payload.cwd // empty' 2>/dev/null)
    [ -z "$id" ] && id=$(basename "$f" .jsonl | rev | cut -d- -f1-5 | rev)
    # The first few "user" turns are injected preamble (AGENTS.md, permissions,
    # environment context), not anything the human typed. Skip them, and flatten
    # each message to one line so the filter matches whole messages not stray lines.
    label=$(jq -r 'select(.type=="response_item") | .payload | select(.role=="user")
                   | .content[]? | select(.type=="input_text") | (.text | gsub("\n"; " "))' "$f" 2>/dev/null \
            | grep -v -e '^#' -e '^<permissions' -e '^<environment_context' -e '^<user_instructions' -e '^<INSTRUCTIONS' -e '^ *$' \
            | head -1 | cut -c1-70)
    emit codex "$(iso "$m")" "$id" "${cwd:-?}" "${label:-?}"
  done < <(find "$HOME/.codex/sessions" -name '*.jsonl' -type f 2>/dev/null)
fi

# ---------- omp : ~/.omp/agent/sessions/<path-slug>/<ts>_<uuid>.jsonl ----------
OMP_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/sessions"
if [ -d "$OMP_DIR" ]; then
  while IFS= read -r f; do
    m=$(mtime "$f"); in_window "$m" || continue
    id=$(jq -r 'select(.type=="session") | .id' "$f" 2>/dev/null | head -1)
    cwd=$(jq -r 'select(.type=="session") | .cwd' "$f" 2>/dev/null | head -1)
    # omp records an auto-generated title, which beats a truncated first prompt
    label=$(jq -r 'select(.type=="title") | .title' "$f" 2>/dev/null | head -1 | cut -c1-70)
    [ -z "$id" ] && id=$(basename "$f" .jsonl | cut -d_ -f2)
    [ -z "$cwd" ] && cwd="(slug) $(basename "$(dirname "$f")")"
    emit omp "$(iso "$m")" "$id" "${cwd:-?}" "${label:-?}"
    # -maxdepth 2 is load-bearing: sub-agent transcripts live one level deeper, in
    # a <ts>_<uuid>/ directory, and are not resumable top-level sessions.
  done < <(find "$OMP_DIR" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null)
fi
