---
name: notify-via-telegram
description: Send a one-shot Telegram message to the user via the locally-installed Hermes CLI. Use when the user is away from the terminal and a status change needs to surface — a long task finished, CI failed, you're blocked needing input, an autonomous loop hit a decision point. Fire-and-forget; there is no reply channel. Trigger phrases include "ping me on Telegram", "tell me when X", "let me know when this is done", "notify me", and also autonomous use after a long-running task completes or stalls while the user appears away.
---

# Notify User via Telegram

Fire-and-forget Telegram notification through the local Hermes gateway. There is no read-back path — do not wait, poll, or expect a reply in this session.

## The command

```bash
/Users/tanvibhakta/.hermes/hermes-agent/venv/bin/hermes send \
  --to telegram \
  --subject "[<short-context>]" \
  "<message>"
```

- `--to telegram` (bare, no chat id) routes to the user's default chat (`TELEGRAM_HOME_CHANNEL`).
- `--to telegram:<chat_id>` targets a specific chat if the user gave you one.
- `--subject` is prepended as a header line — use it to identify *which* Claude is pinging, since the user may have several running.
- `hermes send` posts directly to Telegram's Bot API using the token in `~/.hermes/.env`. It does not need the Hermes gateway daemon running, and uses no LLM.

## Subject discipline

The user will get multiple pings from multiple Claude sessions. Always make it easy for them to tell which one. Format the subject as:

```
[<basename-of-cwd> · <one-word-state>]
```

Examples:
- `[vibechk · done]`, `[vibechk · blocked]`, `[vibechk · failed]`, `[careers-port · review]`

Get cwd's basename with `basename "$PWD"` in the same Bash call.

## What to send

One short, complete sentence the user can act on without opening the laptop. State, not narration.

Good:
- `Phaser review-fixes branch green. PR #4231 open: <url>`
- `Blocked: codex paused asking which DB to use for the first full-suite test. Reply "neon" or "docker".`
- `Test suite failed on rebase: 3 failures in workers/orchestrator. Logs in /tmp/run.log on this Mac.`

Bad:
- Progress noise (`step 4 of 12 starting…`)
- Anything that needs the user to dig through the laptop to understand
- Walls of context — pipe long bodies through `--file` instead

## When NOT to use this

- The user is right there in the same terminal — talk to them in the conversation, don't ping their phone.
- You merely *might* need input later — wait until you actually do.
- Mid-stream progress updates inside a single task.
- Anything where you'd then want to *receive* their reply in this session. The reply path does not exist. If you need a real back-and-forth, stop and tell the user out-of-band conversation isn't supported by this skill.

## Permission rule (one-time setup)

If the first call hits a permission prompt, add this to `~/.claude/settings.json` under `permissions.allow`:

```json
"Bash(/Users/tanvibhakta/.hermes/hermes-agent/venv/bin/hermes send:*)"
```

That allows the exact subcommand globally without giving Claude blanket Bash rights.

## Verify quickly

```bash
/Users/tanvibhakta/.hermes/hermes-agent/venv/bin/hermes send --list telegram
```

Lists configured Telegram targets; exit 0 means the bot token is wired up. This is read-only and safe to run first if you want to confirm the route before sending.
