# Hermes gateway

The Hermes Telegram gateway runs on the always-on MacBook
(`Tanvis-MacBook-Pro.local`, `192.168.0.107`, the same box as Pi-hole). The
laptop keeps the `hermes` CLI as a client only.

Not wired into `hot-sauce/setup.sh`. Exactly one machine may run the gateway.

## Setup

From the laptop:

```sh
cd hot-sauce/services/hermes-gateway
./setup.sh                  # or ./setup.sh <ssh-host>
```

The script:

1. Clones `NousResearch/hermes-agent` on the always-on Mac at the **same commit**
   as the laptop's checkout, then builds its venv with `setup-hermes.sh`.
2. Uninstalls the laptop's gateway launch agent (`ai.hermes.gateway`).
3. Copies `~/.hermes` across, **first run only**.
4. Installs and starts the gateway launch agent there, and waits until
   `gateway_state.json` reports Telegram `connected`.
5. Checks that `hermes send --list telegram` still works from the laptop.

## Why the gateway can only live in one place

Telegram bots receive messages by long-polling `getUpdates`, and Telegram
allows one poller per bot token. Two gateways on the same token knock each
other off with `409 Conflict`, and each message lands on whichever machine
polled last. Sending is different: `hermes send`, which the
`notify-via-telegram` Claude skill uses, is a one-shot Bot API POST. It needs
the token in `~/.hermes/.env` but no gateway, so the laptop can still send.

## Traps

- **Intel Mac.** The always-on Mac is `x86_64`, so Homebrew is in `/usr/local`,
  not `/opt/homebrew`. Over non-interactive SSH, `PATH` is bare, so
  `/usr/bin/git` gets picked and fails on `gpg.format = ssh` in `~/.gitconfig`.
  The script prefixes `/usr/local/bin`. `hermes gateway install` writes the
  current `PATH` into the plist, so the gateway inherits it too.
- **arm64 binaries.** `~/.hermes/bin/tirith` and `~/.hermes/lsp/` are built
  for Apple Silicon and aren't copied. Hermes fetches them again on demand.
- **Reruns don't copy data again.** After the move, the always-on Mac owns its
  sessions, memories and cron jobs. A rerun copying the laptop's stale
  `~/.hermes` would overwrite them. `HERMES_RESYNC=1 ./setup.sh` forces a copy.
  The laptop's gateway is stopped first, so the copy is safe.
- **Desktop login.** `launchctl bootstrap gui/501` only works while someone is
  logged into the always-on Mac's desktop. That's fine for an always-on box, but
  after a reboot with no auto-login the gateway won't come back until you log in.
- **Cron jobs move with the gateway.** Hermes runs its cron scheduler inside the
  gateway process. A job that calls scripts with paths on the laptop will fail
  on the always-on Mac. Pause it with `hermes cron pause <id>` there.

## Operating it

```sh
ssh Tanvis-MacBook-Pro.local
~/.hermes/hermes-agent/venv/bin/hermes gateway status
tail -f ~/.hermes/logs/gateway.log
```

To move the gateway back to the laptop, run `hermes gateway uninstall` on the
always-on Mac, then `hermes gateway install` on the laptop.
