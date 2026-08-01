---
name: writing-commits
description: Use whenever authoring or rewriting a git commit message in the vibechk repo — before running `git commit`, before drafting a `-m` body, before amending, or when fixing a rejected commit. Encodes the actual commitlint rules enforced by `commitlint.config.mjs` + `config/commitlint/sections.mjs` and the lefthook `commit-msg` hook so the message clears both the local hook and CI's PR commit-lint step.
---

# Writing Commits

This skill is the **procedure** for producing a commit message that passes the local `commit-msg` lefthook (`bunx commitlint --edit`) and the CI `Lint commit messages` step. The repo invariants live in `AGENTS.md`; this file is the playbook that operationalizes them and adds the rules from `commitlint.config.mjs` and `config/commitlint/sections.mjs` that AGENTS.md does not spell out.

## Mandatory Checklist (create TodoWrite items)

1. ☐ Pick a Conventional Commit `type` from: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`. No others (rejected by `@commitlint/config-conventional`).
2. ☐ Header ≤ **100 chars** total, lowercase imperative, **no trailing period**. Optional `scope` in parentheses.
3. ☐ Body: exactly **one blank line** after the header, then content.
4. ☐ Body contains a `Context:` section that explains **WHY** the change exists.
5. ☐ `Context:` text must contain at least one rationale token from the allowlist below, or an issue ref like `#97`.
6. ☐ Body must **not** contain a `Verification:` section (forbidden by `sections.mjs`).
7. ☐ Put concrete `Context:` content **on the same line as the `Context:` header** (see "Footer-leading-blank trap" below).
8. ☐ Dry-run before committing: `(cd "$(git rev-parse --show-toplevel)" && bunx commitlint --edit "$MSG_FILE" --verbose)` (`MSG_FILE` from Procedure step 3 — never `/tmp`).
9. ☐ Commit with HEREDOC so newlines survive the shell quoter.

## Rationale-Token Allowlist (Context: WHY-words)

Picked verbatim from `CONTEXT_RATIONALE_PATTERN` in `config/commitlint/sections.mjs`. At least one must appear in the `Context:` body:

- An issue reference matching `#\d+` (e.g. `#97`)
- One of: `avoid`, `because`, `constraint`, `due to`, `intent`, `invariant`, `must`, `need`, `needed`, `needs`, `pressure`, `prevent`, `problem`, `regression`, `request`, `requested`, `required`, `requires`, `risk`, `so that`, `unblock`, `why`

If none appear, commitlint emits `Context section needs WHY: …` and the commit fails.

## Footer-Leading-Blank Trap (observed on this branch)

The commitlint parser interprets `Context:` and `Changes:` lines as Conventional-Commits **footer tokens**. If `Context:` sits on its own line followed by a blank line and then a paragraph, the parser treats the paragraph as body and the next token (or end-of-message) as a footer that lacks a leading blank line. It does not fail, but it raises:

```
⚠   footer must have leading blank line [footer-leading-blank]
```

This appeared on multiple recent commits on `phaser-on-careers` (e.g. `fix(test): retry vite port conflict messages`, `fix(repo): reconcile rebase fallout`).

**Fix**: put the first sentence of context on the same line as the `Context:` header. Same for `Changes:`. Example that passes cleanly: `fix(ci): clear check + unit failures on phaser-on-careers` from this branch's history.

## Closing Issues (Stacked-PR Trap)

If a commit finishes a tracked issue, put the closing keyword in the **commit body**, not (only) the PR description — and never in a comment or the header:

```
Closes #NNN
```

**Why it matters here:** vibechk is rebase-only stacked PRs. GitHub auto-closes an issue only from (a) a PR **description**, which fires only when *that PR* merges into the default branch (main), or (b) a **commit message**, which fires whenever the commit lands on main. A closing keyword in a *child* PR's description that merges into its **parent branch** never fires, and does not retroactively fire when the parent later reaches main. A **comment** never closes anything. Since the commit travels down the whole stack (rebase changes the SHA but preserves the message), the commit-body keyword is the only placement that reliably closes the issue when the work reaches main. Confirmed 2026-07-13: CF14 #855 / CF15 #856 both carried `Closes #NNN` in the PR body and still merged stale-open.

`Closes #NNN` also satisfies the `Context:` WHY-token requirement (the `#\d+` pattern), so it can double as the rationale ref. When a stack already merged stale-open, reconcile by hand: `gh issue close <n> --comment "merged via #<pr>"`.

## Forbidden

- `Verification:` section anywhere in the body (rejected by `sections.mjs`). Routine `bun run check`/`test` evidence belongs in the PR description or final agent response, not the commit.
- Header > 100 chars (auto-rejected).
- Body or footer lines > 600 chars (auto-rejected; effectively a soft limit, but wrap anyway).
- `?? ""`, `?? 0`, `?? false` invariants in the diff that aren't called out in `Context:` — orthogonal to commit-msg lint, but called out because code-style rejects them and an honest `Context:` should name the invariant.
- Empty `Context:` body (the parser sees the header but no meaningful content → rejected).

## Template

```
<type>(<scope>): <imperative subject, ≤100 chars, no period>

Context: <one rationale sentence on this same line, must contain a WHY-word or #issue>. Optional additional sentences continue the same paragraph or wrap to new lines under the Context section.

Changes: <optional mechanical summary on same line, or a bulleted list immediately under this header>.
- bullet one
- bullet two
```

## Procedure

1. Read `AGENTS.md` §Git for repo invariants if you do not already have them in context.
2. Inspect the staged diff: `git diff --cached --stat` and `git diff --cached`. Identify the WHY (user intent, broken invariant, regression, issue ref).
3. Draft the message into a temp file under the LLM workspace — **never `/tmp`** (reboots wipe it, and parallel sessions collide on fixed names):
   ```bash
   MSG_FILE=~/Code/llm-workspace/claude-commit-msg-$(date +%Y%m%d-%H%M%S)-$$.txt
   ```
   Write the message to `$MSG_FILE`. Do **not** start with `git commit -m` directly — multi-line messages need HEREDOC. Note: shell env does not persist between Bash calls, so define `MSG_FILE` (or expand the literal path) in every command that uses it.
4. **Mandatory dry-run** before committing (run from repo root so `commitlint.config.mjs` resolves):
   ```bash
   (cd "$(git rev-parse --show-toplevel)" && bunx commitlint --edit "$MSG_FILE" --verbose)
   ```
   - `found 0 problems, 0 warnings` → ship it.
   - Any `✖ found N problems` → fix and re-run. **Do not** commit on the assumption it will pass.
   - Warnings (`⚠`) like `footer-leading-blank` do not fail CI but ARE a smell — fix unless rewriting would lose clarity. Most often the fix is to inline the first sentence onto the `Context:` line.
5. Commit with the standard repo pattern:
   ```bash
   git commit -F "$MSG_FILE"
   ```
   or HEREDOC:
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <subject>

   Context: <why-text with a rationale token>.
   EOF
   )"
   ```
6. If the lefthook `commit-msg` step rejects the message at commit time, re-read the stderr — it tells you the exact rule. **Do not** bypass with `--no-verify` (see user memory: "Do not use git commit --no-verify").
7. After commit, glance at `git log -1` to confirm the body landed unmangled.

## Quick Self-Check Before Calling It Done

- [ ] Type is one of `feat|fix|refactor|docs|test|chore`.
- [ ] Subject lowercase, imperative, no period, ≤ 100 chars.
- [ ] Exactly one blank line between header and body.
- [ ] `Context:` line carries content on the same line (no naked `Context:\n\n<body>`).
- [ ] `Context:` body contains at least one of the rationale tokens listed above.
- [ ] No `Verification:` section.
- [ ] If this commit finishes a tracked issue: `Closes #NNN` is in the **body** (not a comment/header) — see Closing Issues (Stacked-PR Trap).
- [ ] `bunx commitlint --edit <file>` printed `found 0 problems, 0 warnings`.

If any box fails, do not commit.

## Pointers

- Rules source of truth: `commitlint.config.mjs`, `config/commitlint/sections.mjs`.
- Local enforcement: `lefthook.yml` → `commit-msg.commitlint`.
- CI enforcement: `.github/workflows/ci.yml` → `Check.Lint commit messages` step (PRs only).
- Repo-wide invariants: `AGENTS.md` §Git, §Avoid.
- Test coverage of the parser: `config/commitlint/sections.test.ts` and `tests/repo-policy/commit-hooks.test.ts`.
