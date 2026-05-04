#!/bin/bash
# Block common bad habits in Bash commands.
# Installed at user level so it applies to all projects.

HOOK_INPUT=$(cat)
COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty')

# Match sed or awk used as file-editing commands (not as part of other words like "based")
if echo "$COMMAND" | grep -qE '(^|[|;&\s])sed\s|(^|[|;&\s])awk\s'; then
  cat <<'MSG' >&2
BLOCKED: Do not use sed/awk to edit files.

1. Use the Edit tool instead.
2. If Edit fails due to whitespace mismatch, re-read the file with Read to get exact indentation, then retry Edit with the correct old_string.
3. If the file has inconsistent formatting, run the project formatter first (e.g. `bun run lint:fix` or `bun run format`) and then re-read and retry Edit.

NEVER fall back to sed/awk.
MSG
  exit 2
fi

# Block git -C <path> when the working directory is already the target repo.
# Using -C creates a different command string that won't match existing permission
# allow-rules, forcing the user to re-approve every time.
if echo "$COMMAND" | grep -qE '(^|[|;&])git\s+-C\s'; then
  cat <<'MSG' >&2
BLOCKED: Do not use `git -C <path>`.

Using `-C` creates a different command string that won't match existing permission allow-rules, forcing the user to re-approve every time.

Instead:
1. Check if your current working directory is already the target repo.
2. If it is, use plain `git` commands (e.g. `git status`, `git diff`).
3. If it isn't, `cd` to the target directory first, then run plain `git` commands.
MSG
  exit 2
fi

exit 0
