#!/bin/bash
# Block common bad habits in Bash commands.
# Installed at user level so it applies to all projects.

HOOK_INPUT=$(cat)
COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty')

# Block sed/awk/perl only when they write a file: in-place flags, or a redirect to a
# file. Blocking every sed/awk sent agents into retry loops on plain reads (76 blocks
# in one week, all of them reads). Quoted strings are stripped first, so a '>' inside
# an awk program or "sed -i" inside a commit message is not taken for a command.
UNQUOTED=$(printf '%s' "$COMMAND" | perl -0pe "s/'[^']*'//g; s/\"(?:\\\\.|[^\"\\\\])*\"//g")
EDITING=$(printf '%s\n' "$UNQUOTED" | tr '|;&' '\n\n\n' | perl -ne '
  next unless /^\s*(?:\w+=\S*\s+)*(?:sudo\s+)?(g?sed|g?awk|perl)\s/;
  my $tool = $1;
  s{\d*>>?\s*/dev/(?:null|stdout|stderr)}{}g;
  s{\d>>?}{}g;
  if (($tool =~ /sed/ && /\s(?:-[a-zA-Z]*i|--in-place)/)
      || ($tool =~ /awk/ && /\s-i\s*inplace/)
      || ($tool eq "perl" && /\s-[a-zA-Z]*i/)
      || ($tool ne "perl" && />/)) { print; exit }')
if [ -n "$EDITING" ]; then
  cat <<'MSG' >&2
BLOCKED: this sed/awk/perl command writes a file (-i, -i inplace, or a > redirect).

1. To edit a file, use the Edit tool. If Edit fails on whitespace, re-read with Read to get exact indentation and retry.
2. To view a line range, use Read with offset/limit.
3. To filter output, read-only sed -n / awk / rg / jq / cut are fine, without -i or a redirect to a file.
MSG
  exit 2
fi

# Block git -C <path> when the working directory is already the target repo.
# Using -C creates a different command string that won't match existing permission
# allow-rules, forcing the user to re-approve every time.
if echo "$COMMAND" | grep -qE '(^|[|;&[:space:]])git[[:space:]]+-C[[:space:]]'; then
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

# Block committing while HEAD is the default branch — vibechk only. Work there belongs
# on a branch in a worktree. This fires even with `git commit --no-verify`, which is
# the gap the lefthook commit-msg/pre-commit hooks cannot cover. Checks the cwd's
# repo, so a session inside a worktree is judged by that worktree's own HEAD. Other
# repos (dotfiles, scratch projects) commit to main directly, so they are left alone.
if echo "$COMMAND" | grep -qE '(^|[|;&[:space:]])git[[:space:]]+([^|;&]*[[:space:]])?commit([[:space:]]|$)' \
  && git remote get-url origin 2>/dev/null | grep -qE '[:/]Alt-AI-Inc/vibechk(\.git)?$'; then
  BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    cat <<MSG >&2
BLOCKED: refusing to commit while HEAD is "$BRANCH".

All work goes on a branch, in a worktree — never in the main checkout. The main
clone is also swept back to the default branch by a scheduled git-pull job, so a
branch created there can be switched out from under you and the commit lands on
$BRANCH.

Instead:
1. Use EnterWorktree to get an isolated worktree with its own HEAD.
2. If you already have commits stranded on $BRANCH: point a branch at them
   (git branch <name> <sha>), then reset $BRANCH back (git branch -f $BRANCH origin/$BRANCH).
MSG
    exit 2
  fi
fi

exit 0
