#!/bin/bash
# Warn before a vibechk commit that stages visual files Tanvi has not approved.
# Approval is recorded by touching <worktree>/.tmp/ui-approved AFTER she approves the
# rendered HTML page in her browser; any staged src/ui/** or packages/*-web/** file newer
# than that stamp means the commit contains UI she has not seen.

HOOK_INPUT=$(cat)
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // empty')
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty')

printf '%s' "$COMMAND" | rg -q '\bgit\b.*\bcommit\b' || exit 0
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
git remote get-url origin 2>/dev/null | rg -q 'vibechk' || exit 0
cd "$TOP" || exit 0

STAGED=$(git diff --cached --name-only --diff-filter=ACMR \
  | rg '^(src/ui/|packages/[^/]+-web/)' \
  | rg -v '\.(test|spec)\.[jt]sx?$|/__tests__/|\.md$')
[ -z "$STAGED" ] && exit 0

STAMP="$TOP/.tmp/ui-approved"
STAMP_MTIME=0
[ -f "$STAMP" ] && STAMP_MTIME=$(stat -f %m "$STAMP")

UNAPPROVED=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  [ "$(stat -f %m "$f")" -gt "$STAMP_MTIME" ] && UNAPPROVED="$UNAPPROVED $f"
done <<< "$STAGED"
[ -z "$UNAPPROVED" ] && exit 0

MSG="UI approval check: staged visual files changed after the last approval stamp (.tmp/ui-approved):${UNAPPROVED}. Before committing, render the real component as an HTML page, \`open\` it in Tanvi's browser, and wait for her approval; then \`touch .tmp/ui-approved\`. Do not add headings, captions or helper text she did not ask for. If this change has no visual effect, say so to her instead of stamping."
jq -n --arg msg "$MSG" '{
  systemMessage: $msg,
  hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $msg }
}'
exit 0
