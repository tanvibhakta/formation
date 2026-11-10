#!/usr/bin/env bash
# Register Doist's official hosted Todoist MCP server for Claude Code (user scope).
# Idempotent. Auth is OAuth: after running, open /mcp in Claude Code and pick
# "todoist" -> Authenticate. No token is stored here, so this file is committable.
set -euo pipefail

NAME=todoist
URL=https://ai.todoist.net/mcp

if claude mcp get "$NAME" >/dev/null 2>&1; then
  echo "$NAME MCP already registered"
else
  claude mcp add --scope user --transport http "$NAME" "$URL"
fi

claude mcp get "$NAME"
