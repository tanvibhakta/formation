---
description: Create a Linear issue with consistent formatting
argument-hint: [issue description]
allowed-tools: Bash(linear:*)
---

You are creating a Linear issue using linear-cli. Be extremely concise.

LABELS AVAILABLE: bug, enhancement, documentation, critical, high, medium, low, epic, shared-package, logging

REQUIREMENTS:
1. Show issue structure BEFORE creating
2. Title: Brief description
3. Description: Problem + 2-3 acceptance criteria bullets
4. Type: Feature/Bug/Task
5. Labels: Select 2-3 relevant ones
6. Project: REQUIRED - if unclear, run 'linear project list' and ask user to choose
7. Assignee: Creator
8. Create with 'linear issue create' and return URL

PROCESS:
1. First run 'linear project list' to get available projects
2. Determine appropriate project (prompt user if unclear)
3. Show complete issue structure for approval
4. Create issue using linear-cli
5. Output final issue URL

Issue description: $ARGUMENTS