# op-remote for Hermes

Hermes on the always-on Mac gets a 1Password secret only after Tanvi taps
**Approve** in Telegram, once per request. It uses a patched
[op-remote](https://github.com/wyattjoh/op-remote) and a dedicated bot,
**@TanviSecretApprovalsBot**.

## How it works

1. Hermes starts op-remote as its `op-remote` MCP server, as the hidden user
   `_opremote`: `sudo -n -u _opremote /opt/op-remote/serve.sh`.
2. op-remote knows the *names and `op://` references* of every hidden field in the
   `alt.inc` and `Private` vaults (`/var/opremote/run/secrets.env.tpl`, built at
   sign-in). It holds no secret values.
3. To use a secret, Hermes calls the `request_token` tool, then runs
   `/opt/op-remote/bin/op-remote run --token=… --sock=… --env-file=/var/opremote/run/secrets.env.tpl --reason="…" -- <command>`.
4. The bot sends Tanvi the command, the reason and the secret names, with
   Approve / Reject / Stop. On Approve, op-remote runs `op read` for just those
   references and passes the values to that one command over a local socket.
   Values never go through Telegram.

The approvals use their own bot, not Hermes's. Through Hermes's gateway, Hermes
would carry its own approval and could approve itself.

## Isolation

| What | Owner, mode | Why |
| --- | --- | --- |
| `/opt/op-remote/` (code, `op`, `bun`) | root, 0755 | Hermes can run it but not change it |
| `/var/opremote/` | `_opremote:staff`, 0710 | Hermes can pass through, not list |
| `/var/opremote/session` | `_opremote`, 0600 | the 1Password session; Hermes can't read it |
| `/var/opremote/run/` and the socket | `_opremote:staff`, 0750 / 0660 | Hermes's only way in |
| `/etc/sudoers.d/op-remote` | root, 0440 | Hermes may run `serve.sh` as `_opremote`, nothing else |

macOS is Unix: the kernel stops one user's processes reading another user's
files, memory or environment. `_opremote` has no password and no login shell.

## Patch (`patch.py`)

Upstream op-remote resolves every secret at startup and keeps the values. The patch:

- stores references only and runs `op read` after each approval;
- keeps the CLI session alive with `op whoami` every 10 minutes (sessions expire
  after 30 minutes idle);
- removes the Auto-Approve button (one tap approved every later request);
- puts the socket in `/var/opremote/run` with mode 0660.

Each edit must match exactly, so an upstream change fails loudly. `isolate.sh`
downloads op-remote from the npm registry and checks its sha512 there, and
requires the expected code-signing team for `op` (AgileBits, `2BUA8C4S2C`) and
`bun` (`7FRXF46ZSN`).

## Setup

From the laptop, in a real terminal (sudo on the server asks for your password):

```sh
hot-sauce/services/op-remote/setup.sh
ssh -t Tanvis-MacBook-Pro.local 'sudo -u _opremote /opt/op-remote/signin.sh && ~/.local/bin/hermes gateway restart'
```

The first sign-in as `_opremote` asks for your Secret Key and password; later ones
ask for the password only.

## Traps

- **Sign in again after every gateway restart or reboot.** The session lives only
  while op-remote keeps it alive.
- **New 1Password items need a new sign-in** (or rerun `gen-secrets.py`) before
  Hermes can name them.
- **The trust moment is the install.** `setup.sh` stages files in `/tmp` and the
  root script trusts them. Run it when Hermes isn't mid-task.
- **Approved secrets reach the command Hermes runs.** Approval controls which
  secrets Hermes gets and when, not what it does with them afterwards.

## Remove

```sh
sudo rm -rf /opt/op-remote /var/opremote /etc/sudoers.d/op-remote
sudo dscl . -delete /Users/_opremote; sudo dscl . -delete /Groups/_opremote
# then delete the op-remote entry from ~/.hermes/config.yaml and restart the gateway
```
