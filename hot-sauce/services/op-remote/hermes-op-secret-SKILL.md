---
name: op-secret
description: Use when you need API keys, credentials, passwords or other secrets (Alt Inc or personal). Secrets come only through op-remote, which asks Tanvi to approve each request in Telegram.
---

# Secrets via op-remote

You cannot read 1Password directly. `op` on this machine is not signed in for you,
and that is deliberate. Every secret goes through op-remote, and Tanvi approves each
request on her phone.

## Steps

1. **Find the names.** The master list is `/var/opremote/run/secrets.env.tpl`. Each
   secret has a readable label line, then its `NAME=op://…` line:
   ```
   #: ALT_INC__RENDER_API_KEY__CREDENTIAL	alt.inc › Render API key › credential
   ALT_INC__RENDER_API_KEY__CREDENTIAL=op://…
   ```
   Search it with `grep -i`. Names are `VAULT__ITEM__FIELD`.
2. **Write a small env file with only what this command needs**, label lines included:
   ```bash
   grep -B1 -E '^(ALT_INC__RENDER_API_KEY__CREDENTIAL)=' /var/opremote/run/secrets.env.tpl > "$TMPDIR/needed.env"
   ```
   Tanvi sees every name in the file, so never pass the whole master list.
3. **Call the `request_token` tool** (op-remote MCP server). It returns `token` and `sock`.
4. **Run the command through op-remote**:
   ```bash
   /opt/op-remote/bin/op-remote run --token=TOKEN --sock=SOCK \
     --env-file="$TMPDIR/needed.env" \
     --reason="One plain sentence saying what this is for" \
     -- curl -s -H "Authorization: Bearer $ALT_INC__RENDER_API_KEY__CREDENTIAL" https://api.render.com/v1/services
   ```
   The command waits until Tanvi taps Approve or Reject. Secret values in its output
   are masked. Delete `$TMPDIR/needed.env` afterwards.

## Rules

- **The reason must be honest and specific.** Tanvi decides from it and from the command.
  Name the task she asked for.
- **Request the fewest secrets that work.** One request per task, not a batch "just in case".
- **Never print, log, store or send a secret anywhere except the service it belongs to.**
  Don't echo it, write it to a file, or put it in a message.
- **Rejected means stop.** If she rejects, or op-remote says the session is stopped, don't
  retry or look for another route. Tell her and wait. Use the `resume` tool only if she
  asks you to.
- **"1Password read failed … may need signing in again"** means the server's 1Password
  session lapsed. Tell her to run:
  `ssh -t Tanvis-MacBook-Pro.local 'sudo -u _opremote /opt/op-remote/signin.sh && ~/.local/bin/hermes gateway restart'`
- Never try to read `/var/opremote` beyond the list, use `sudo`, or run `op` directly.
