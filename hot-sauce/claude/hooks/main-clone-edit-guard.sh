#!/bin/bash
# Refuse Edit/Write/MultiEdit/NotebookEdit inside vibechk's shared main clone — vibechk only.
# Every session and the scheduled git-pull job share that checkout, so an edit there collides
# with other sessions (two user interventions in one week, 2026-09-21..28). Worktrees under the
# clone and its .tmp/ scratch dir stay writable.

HOOK_INPUT=$(cat)
TARGET=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -z "$TARGET" ] && exit 0

git remote get-url origin 2>/dev/null | grep -qE '[:/]Alt-AI-Inc/vibechk(\.git)?$' || exit 0

COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ "$(basename "$COMMON")" = ".git" ] || exit 0
CLONE=$(dirname "$COMMON")

case "$TARGET" in
  "$CLONE"/.tmp/* | "$CLONE"/.claude/worktrees/* | "$CLONE"/.worktrees/*) exit 0 ;;
  "$CLONE"/*) ;;
  *) exit 0 ;;
esac

cat <<MSG >&2
BLOCKED: $TARGET is in the shared main clone, which every session and the scheduled git-pull job also use.

1. EnterWorktree first, then make this edit at the same path inside the worktree.
2. Scratch files may go in the clone's .tmp/.
MSG
exit 2
