# Laptop SSH (from the always-on Mac)

Lets the Hermes gateway on the always-on Mac (`192.168.0.107`, see
`services/hermes-gateway`) run commands on this laptop over SSH:
`ssh big-macbook` from there.

Run on the laptop:

```sh
hot-sauce/services/laptop-ssh/setup.sh
```

It asks for your password once: with `sudo` in a terminal, or with the macOS
dialog when run with no terminal (e.g. `!` from Claude Code). It is idempotent,
and it finishes by SSHing in from the always-on Mac to prove the setup works.

## What it sets up

- **A dedicated key**, `~/.ssh/id_ed25519_big_macbook`, generated on the
  always-on Mac with no passphrase so Hermes can use it unattended. Its existing
  `id_rsa` is left alone.
- **`authorized_keys` entry pinned with `from="192.168.0.107"`**, with agent,
  port and X11 forwarding off. A copied key won't work from anywhere else.
- **sshd hardening** in `/etc/ssh/sshd_config.d/050-hot-sauce.conf`: no
  password or keyboard-interactive logins, no root, `AllowUsers` this user only.
  sshd keeps the *first* value it reads, and the drop-ins are read in
  alphabetical order, so the file has to sort before macOS's `100-macos.conf`.
- **Remote Login on**, via `launchctl` rather than
  `systemsetup -setremotelogin on`. On recent macOS, `systemsetup` fails unless
  the terminal has Full Disk Access.
- **`Host big-macbook`** in the always-on Mac's `~/.ssh/config`, pointing at
  `Tanvis-Big-MacBook-Pro-2.local`. The `.local` name means the laptop's own
  DHCP address can change without breaking this.

## Traps

- **No host keys on a Mac that has never had Remote Login on.** macOS
  creates `/etc/ssh/ssh_host_*` the first time sshd starts, so `sshd -t` fails
  beforehand with `no hostkeys available`. The script runs `ssh-keygen -A`
  first.

- **The laptop leaves the house with sshd listening.** On other networks,
  passwords are off and the only accepted key is pinned to a LAN IP, so there's
  nothing to log in with. It's still an open port; turn it off with
  `sudo launchctl disable system/com.openssh.sshd && sudo launchctl bootout system/com.openssh.sshd`.
- **`from=` depends on `192.168.0.107` staying put.** That's the Pi-hole host's
  manual IP. If it changes, update `REMOTE_IP` and rerun.
- **Hermes approvals have no buttons in Beeper.** Beeper doesn't show
  Telegram's inline buttons. Answer with `/approve` (once), `/approve session`,
  `/approve always` or `/deny`, and add `all` to answer every pending one.

## Undo

```sh
sudo rm /etc/ssh/sshd_config.d/050-hot-sauce.conf
sudo launchctl disable system/com.openssh.sshd
sudo launchctl bootout system/com.openssh.sshd
# then delete the "hermes@always-on -> big-macbook" line from ~/.ssh/authorized_keys
```
