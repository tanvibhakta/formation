---
name: reopen-ghostty-agent-sessions
description: Use when coding-agent sessions that were open in Ghostty tabs need to be brought back after a system restart, crash, power loss, accidental Cmd+W/Cmd+Q, or app quit - "reopen the sessions that were open before the shutdown", "I accidentally closed all my sessions", "restore my tabs", "put them back in the order they were in". Finds which Claude Code, Codex, and omp sessions were live at the moment everything died, reopens each in its own tab in the original left-to-right order, and verifies every one actually came back.
---

# Reopen agent sessions in Ghostty

Sessions survive; tabs do not. Every harness writes its transcript to disk continuously,
so the work is intact — the loss is purely the *arrangement*: which sessions were open,
and in what order.

Everything here is shell and `osascript`, so it works whichever harness you are running
inside (Claude Code, Codex, omp, anything else).

**The one rule that governs everything below: trust processes, not the UI.** Ghostty's
accessibility (AX) API goes stale constantly and returns confident, wrong answers —
`count of windows` reports 0 while windows are plainly visible, and a window title can
read as a tab that is not actually focused. Every guard in this skill is built on the
process tree because an AX-based guard has already closed the wrong tab and killed a live
session. Read that sentence again before you write any `keystroke "w"`.

## Order matters, and it is the part that expires

Ask for a screenshot of the tab bar in your **first reply**, before doing anything else.

Ghostty's saved state (`~/Library/Saved Application State/com.mitchellh.ghostty.savedState/`)
is rewritten within minutes of the app restoring, and what it restores is often a *stale*
layout from an older session, not the one that just died. Once overwritten, the original
order is gone from disk permanently. A screenshot is usually the only authoritative
record — and people often have one, because they took it while watching things go wrong.

If no screenshot exists, say so plainly and offer the fallback: order by when each session
was first created, which approximates tab order because tabs are appended as they are
opened. Do not present the fallback as the real order.

## Step 1 — Pin the cutoff

For a restart or crash, the machine's boot time *is* the moment of death:

```bash
sysctl -n kern.boottime
last reboot | head -3
```

For an accidental close there is no boot event; use the wall-clock time the user gives you.

## Step 2 — Find what was live

```bash
scripts/discover-sessions.sh                 # cutoff = last boot
scripts/discover-sessions.sh --within 10     # closed ~10 minutes ago
scripts/discover-sessions.sh --at '2026-08-12 10:45' --window 3
```

Output is `harness / last_write / session_id / cwd / label`, covering all three harnesses.
It works on the signal that a live session's transcript is *warm*: agents flush on nearly
every turn, so files written in the last few minutes before the cutoff were open, and a
session closed an hour earlier was not.

| Harness | Session store | Resume |
|---|---|---|
| Claude Code | `~/.claude/projects/<cwd-slug>/<uuid>.jsonl` | `claude --resume <uuid>` |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*-<uuid>.jsonl` | `codex resume <uuid>` |
| omp | `~/.omp/agent/sessions/<path-slug>/<ts>_<uuid>.jsonl` | `omp --resume=<uuid>` |

Expect a tight cluster of files sharing almost the same timestamp — that cluster is your
set. Widen `--window` if it looks short, and check the count against the screenshot.

Show the user the list with a one-line description of each *before* opening anything. It is
how they catch a session that should not come back, and how you catch one that is missing.

## Step 3 — See what is actually open right now

```bash
scripts/map-tabs.sh
```

One line per tab: `shell=<pid> self=<yes|no> agent=<command | IDLE>`. This is the only
trustworthy picture of the window. After a restart Ghostty typically reopens a window full
of **idle shells** from an old layout — they are not your sessions, and leaving them means
the restored set is buried among decoys.

`self=yes` marks the tab you are running in. Never close it.

## Step 4 — Open them, in order

```bash
scripts/open-session-tab.sh "cd '/path/to/cwd' && claude --resume <uuid>"
scripts/open-session-tab.sh "cd '/path/to/cwd' && codex resume <uuid>"
scripts/open-session-tab.sh "cd '/path/to/cwd' && omp --resume=<uuid>"
```

**One invocation per session, in left-to-right target order.** The script presses Cmd+9
(`last_tab`) before Cmd+T, so each new tab lands at the end and the order comes out right
by construction — no reordering step needed. This is the single most important thing here.

That Cmd+9 is load-bearing: Ghostty's `window-new-tab-position` defaults to `current`, so a
new tab is inserted immediately *after the active tab*, not at the end. Without the jump,
tabs interleave into the middle of the bar in the order you least expect.

The script verifies a new shell actually appeared before typing anything. `cd` first —
every harness resolves a session id against the working directory. Because the command is
`cd X && resume`, a dropped keystroke in the `cd` silently short-circuits and the tab just
sits at a prompt, which is why the next step is not optional.

## Step 5 — Verify

```bash
scripts/map-tabs.sh
```

Count agents, not tabs, and compare against the expected set. Re-run any session that did
not start. Then show the user the final layout.

## Closing tabs safely

Never close a tab with `Cmd+W` behind an AX title check. That check reads a stale value
often enough to matter, and the cost of being wrong is a killed session.

Close by killing the tab's login shell, from `map-tabs.sh` output:

```bash
kill <shell-pid>     # only where agent=IDLE and self=no
```

Deterministic, needs no focus, and cannot hit the wrong tab. If you must close a tab
running an agent, exit it from inside that session instead.

## Repair path: fixing order without restarting sessions

Only when tabs already exist in the wrong order and you do not want to restart them.
**Requires healthy AX** — if `count of windows` is returning 0, this path is unavailable
and closing/reopening in order is the honest fallback.

`move_tab` exists but Ghostty binds it to nothing, so add two keybinds temporarily:

```bash
cp ~/.config/ghostty/config /tmp/ghostty-config.bak && shasum ~/.config/ghostty/config
printf '\nkeybind = super+ctrl+alt+shift+right=move_tab:1\nkeybind = super+ctrl+alt+shift+left=move_tab:-1\n' >> ~/.config/ghostty/config
ghostty +validate-config          # then Cmd+Shift+comma in the app to reload
```

Drive the sort from a shell loop, one move per invocation:

```bash
for i in $(seq 1 60); do
  out=$(osascript scripts/reorder-step.applescript "substr 1" "substr 2" ...)
  echo "$out"; case "$out" in SORTED*|ERROR*) break;; esac
done
```

Restore the config afterwards and confirm with `shasum`, then reload again. Note that
repeated config reloads appear to be what degrades AX in the first place.

## Gotchas that will bite you

**Never use `open -na Ghostty --args … -e <cmd>`.** It launches a *separate app instance*
per call, and each restores the saved multi-tab layout. Nine sessions become nine windows
of nine tabs each. Use Cmd+T into the existing instance.

**`ghostty +new-window` is not supported on macOS.** The action appears in `+list-actions`
but refuses to run, so there is no IPC route in.

**AX degradation can become persistent.** It usually sets in after config reloads and tab
moves. Clicking a Window-menu entry re-registers the handle — but that click *changes the
active tab*, so it must never run between selecting a tab and acting on it. `killall
"System Events"` does **not** fix it.

**`pgrep -f` does not reliably match the main ghostty process, and `pgrep -P` omits your
own tab's shell.** Use `ps -Ao pid=,ppid=,args=` for both. `map-tabs.sh` already does.

**Tab titles lie.** Agents rewrite their title as work progresses, the status glyph
animates, and a title reverts to the bare cwd the moment its command exits. Match on stable
substrings, and never treat a title as proof of what a tab contains.

## Prevention

`confirm-close-surface = false` means Cmd+W closes a tab instantly with no dialog, and
Ghostty has exactly one confirmation knob governing tab-close and quit together — so
"confirm on Cmd+Q but not Cmd+W" is not expressible in config. The existing mitigation is a
`cmd+q>cmd+q` key *sequence*, which disarms a single reflexive Cmd+Q without putting a
dialog on Cmd+W.
