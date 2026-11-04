#!/usr/bin/env bash
# List coding-agent sessions that were alive at a cutoff moment, across every
# harness installed on this machine. Output is TSV:
#   harness <TAB> last_write <TAB> session_id <TAB> resume_dir <TAB> label
#
# Usage:
#   discover-sessions.sh                # cutoff = last transcript write before boot (restart case)
#   discover-sessions.sh --within 10    # cutoff = now, look back 10 minutes (close case)
#   discover-sessions.sh --at '2026-08-12 10:45' --window 3
#
# A session counts as "alive at the cutoff" if its transcript was still being
# written within --window minutes before the cutoff. Agents flush on nearly every
# turn, so a live session's file is warm; a session closed an hour ago is not.
#
# resume_dir is the directory to `cd` into before resuming. It is "?" when that
# directory no longer exists, with the recorded path reported on stderr.

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

OMP_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/sessions"

# Top-level transcripts only: Claude Code and omp keep sub-agent transcripts a
# level deeper, and those are not resumable sessions.
list_transcripts() {
  find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null
  find "$HOME/.codex/sessions" -name '*.jsonl' -type f 2>/dev/null
  find "$OMP_DIR" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null
}

if [ -z "$CUTOFF" ]; then
  # Boot time alone is too late a cutoff: a machine can take minutes to shut down
  # and come back, which leaves the final writes outside the window. So anchor on
  # the newest transcript written before boot, which works for a clean restart and
  # a crash alike.
  # kern.boottime prints "{ sec = 1789559884, usec = 352203 }". Anchor on the leading
  # brace: a leading .* would match greedily through "usec" and yield the microseconds.
  boot_epoch=$(sysctl -n kern.boottime | sed -n 's/^{ *sec = \([0-9]*\).*/\1/p' 2>/dev/null)
  [ -z "$boot_epoch" ] && { echo "could not read boot time" >&2; exit 1; }
  last_write=$(list_transcripts | while IFS= read -r f; do stat -f %m "$f"; done \
    | awk -v boot="$boot_epoch" '$1 <= boot && $1 > newest { newest = $1 } END { if (newest) print newest }')
  CUT_EPOCH="${last_write:-$boot_epoch}"
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

# Claude Code stores a transcript under a slug of a directory path, with every
# non-alphanumeric character replaced by "-". That is usually where the session
# started, but a session that enters a worktree is stored under the worktree's slug.
slug_of() { printf '%s' "${1//[^a-zA-Z0-9]/-}"; }

# Find the directory whose slug is $1 by walking down from $2, following only the
# children whose slug is a prefix of the target. The slug cannot simply be decoded,
# because "-" may have been "/", "." or "-".
dir_for_slug() {
  local target="$1" dir="${2:-}" child s
  if [ "$(slug_of "$dir")" = "$target" ]; then printf '%s' "$dir"; return 0; fi
  while IFS= read -r child; do
    s=$(slug_of "$child")
    case "$target" in
      "$s"|"$s"-*) dir_for_slug "$target" "$child" && return 0 ;;
    esac
  done < <(find "${dir:-/}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  return 1
}

# ---------- Claude Code : ~/.claude/projects/<cwd-slug>/<uuid>.jsonl ----------
# Resume from the slug's directory, not a recorded cwd. A session can cd elsewhere
# while it runs and a repo can move, but --resume only looks in the slug of the
# directory it is launched from.
if [ -d "$HOME/.claude/projects" ]; then
  while IFS= read -r f; do
    m=$(mtime "$f"); in_window "$m" || continue
    id=$(basename "$f" .jsonl)
    resume_dir=$(dir_for_slug "$(basename "$(dirname "$f")")") || {
      recorded=$(jq -r 'select(.cwd) | .cwd' "$f" 2>/dev/null | head -1)
      echo "no directory found for ${id}: stored under $(basename "$(dirname "$f")"), first recorded cwd ${recorded:-unknown}" >&2
      resume_dir=""
    }
    label=$(jq -r 'select(.type=="user") | .message.content | select(type=="string")' "$f" 2>/dev/null | head -1 | cut -c1-70)
    emit claude "$(iso "$m")" "$id" "${resume_dir:-?}" "${label:-?}"
  done < <(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null)
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
