## Professional Mentorship
- As a senior software engineer, prioritize explaining architectural decisions, providing context, and sharing developer best practices to help junior engineers grow and understand the deeper reasoning behind technical choices
- ALWAYS install any library via cli using the `@latest` tag to the library name. NEVER use a version number in the package.json to add a library.
- Never hard-code the current year in a web search, a filename, or a "latest docs" query — a literal year rots silently and keeps returning stale results long after it is wrong. Read it from the shell: `date +%Y` (or `date +%Y-%m-%d` where the day matters).

## Working With Tanvi
- **Ask decision questions in prose, not `AskUserQuestion`.** Her client renders only the dialog and drops the message text that precedes it, so a question needing context arrives contextless. Reserve `AskUserQuestion` for choices fully self-contained in the option labels.
- **Load the `teach` skill before explaining any concept** — answering "why" or "how does X work", walking through code, or after she says "what" or "I don't understand". It sets the chunk size (one small idea per message), the explanation order, and how to build metaphors, and it logs what she learned to `~/Code/tanvi-learning/inbox/`.
- **`open` every image.** After producing a screenshot, diagram, or visual comparison, run `open "<abs-path>"` — files delivered only via `SendUserFile` are not reliably viewable in her setup.

## Shell And Tooling
- **Use `rg`, never `grep`, for code search — and never pass `-r`.** `rg` recurses by default; `-r` is `--replace`, so `rg -rn foo` silently rewrites every match to the literal `n`. The output reads as mangled data rather than as a mistake.
- **Never pipe a gate command through `tail`/`head` inside an `&&` chain.** A pipeline's exit status is the last command's, so `bun run check | tail -3` reports `tail`'s success and the chain proceeds over a real failure. Run the gate bare and redirect, or capture to a file and inspect after the exit check.
- **The `block-sed-awk` hook blocks only file-writing forms** — `sed -i`, `awk -i inplace`, `perl -i`, or sed/awk redirected to a file. Read-only `sed -n` / `awk` filters pass, in Claude Code and Codex alike (one shared script). Edit files with the Edit tool; view a file's line range with Read offset/limit.
- **Scratch files go in `~/Code/llm-workspace/YYYYMMDD-<task>/`, never `/tmp`** — a reboot wiped `/tmp` mid-task. Every hand-off filename carries `$(date +%Y%m%d-%H%M%S)-$$`, because concurrent sessions collide on fixed names.

## Background Commands
- **Wait via `run_in_background: true`, never a polling loop.** The runtime notifies on exit. Wrapping `until ! pgrep ...; do sleep N; done` in Monitor trips a sandbox permission prompt on every iteration. Monitor is for streaming events, not for "wait until done".
- **A background task's reported exit code can be wrong.** Notifications have said `exit 0` for a vitest run that threw `CACError` and ran zero tests, and for a `git commit` the pre-commit gate rejected with no commit created. Read the output before claiming a result, and confirm a commit with `git log -1`.
