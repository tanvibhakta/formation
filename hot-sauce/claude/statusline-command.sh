#!/usr/bin/env bash
# Claude Code status line: dir, git, model, cost + worktree ID

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")
model=$(echo "$input" | jq -r '.model.display_name // "?"')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' | xargs printf '$%.2f')

# Git info
git_info=""
if cd "$cwd" 2>/dev/null && git --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks rev-parse --short HEAD)
  if git --no-optional-locks diff --quiet 2>/dev/null && git --no-optional-locks diff --cached --quiet 2>/dev/null; then
    git_info=$(printf '\033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m' "$branch")
  else
    git_info=$(printf '\033[1;34mgit:(\033[0;31m%s\033[1;34m) \033[0;33m✗\033[0m' "$branch")
  fi
fi

# Worktree ID
registry="/Users/tanvibhakta/Code/alt.inc/.altinc-worktrees.json"
worktree_id=0
if [ -n "$cwd" ] && [ -f "$registry" ]; then
  check_dir="$cwd"
  while [ "$check_dir" != "/" ]; do
    matched_id=$(jq -r --arg p "$check_dir" '.worktrees[$p].id // empty' "$registry" 2>/dev/null)
    if [ -n "$matched_id" ]; then
      worktree_id="$matched_id"
      break
    fi
    check_dir=$(dirname "$check_dir")
  done
fi

printf '\033[1;32m➜\033[0m  \033[0;36m%s\033[0m %s \033[0;35m[%s %s]\033[0m wt%s' \
  "$dir" "$git_info" "$model" "$cost" "$worktree_id"
