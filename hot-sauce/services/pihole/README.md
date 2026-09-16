# Pi-hole

Network-wide DNS ad blocking, running in Docker on the always-on MacBook.

Not wired into `hot-sauce/setup.sh` on purpose. Exactly one machine on the LAN
should run this, and it must be one that never leaves the house — every device
you point at it hardcodes its IP, so when the host goes away, so does DNS.

## Setup

On the always-on Mac:

```sh
cd hot-sauce/services/pihole
./setup.sh
```

The script is idempotent. It checks Docker is running, checks nothing else holds
port 53, warns if the machine is still on DHCP, offers to disable sleep,
generates a random admin password into a gitignored `.env`, starts the container,
and then proves DNS actually resolves before telling you it worked.

Admin UI lands on `http://<host-ip>:8053/admin` — 8053 rather than 80 so nginx
and local dev servers keep working.

The host is **`192.168.0.107`**, set manually. That address sits inside the
router's DHCP pool (`192.168.0.100`–`192.168.0.199`), so pin it on the router
too: `Advanced → Network → LAN Settings → Address Reservation → Add`, mapping
the host's MAC to `192.168.0.107`. Without the reservation the router can lease
`.107` to something else while the Mac is off, and you get an address clash that
looks like random DNS failure.

## Pointing devices at it

### The one rule

**Set both primary and secondary DNS to the Pi-hole's IP.** Never put `1.1.1.1`
in the secondary slot.

Clients don't treat the secondary as failover-only — they race both servers and
take whichever answers first. Since Cloudflare will almost always beat a local
container, a `1.1.1.1` secondary means ads leak through more or less constantly
while everything still *looks* configured correctly. This is the exact trap that
sank the first attempt at this setup: `nslookup` came back
`Server: 1.1.1.1` and the reason wasn't obvious.

The tradeoff is real and worth accepting knowingly: with no external fallback,
DNS dies when Pi-hole dies. That's why sleep gets disabled and why the host has
a manual IP.

### Google TV / Android TV

Network → your Wi-Fi → IP settings → Static. Set both DNS fields to
`192.168.0.107`.

### Router (all devices at once) — possible, but ACT hides the fields

The page is `Advanced → Network → LAN Settings` (the "DHCP Server" heading is on
that page; it is not its own menu item). **Not** the WAN DNS page under Internet
— WAN DNS is only what the router itself resolves against and never reaches
clients. An earlier attempt burned a day on WAN DNS, static WAN IP, and Dynamic
DNS for exactly that reason.

On this router — Archer C5 v4, firmware `3.16.0 0.9.1 v6015.0 Build 240806` —
the Primary/Secondary DNS fields are **present but deliberately hidden**:

- `input#dnsserver1` and `input#dnsserver2` live inside `form#formIPv4`, four
  octet cells each, carrying an inline `style="display: none"`, inside a parent
  `div.nd.pure-control-group` that is also `display: none`.
- They are live, not vestigial. They read back `49.205.72.130` and
  `183.82.243.66` — exactly the DNS the router hands out over DHCP. Only the UI
  is suppressed; the backend still serves these values.

So they can probably be set by unhiding the row in devtools and saving:

```js
['dnsserver1', 'dnsserver2'].forEach(id => {
  const el = document.getElementById(id);
  el.style.display = '';
  const row = el.closest('.pure-control-group');
  row.style.display = ''; row.classList.remove('nd');
});
```

Whether the firmware *persists* an edited value is untested — it may ignore or
re-assert ACT's servers on save or reboot. Try it only after Pi-hole is up and
verified, never before: pointing DHCP at a resolver that isn't answering takes
DNS down for every device at once.

**Recovery**, if it misbehaves: same page, restore Primary `49.205.72.130` and
Secondary `183.82.243.66`, save. Worth having open in a second tab first.

Caveats once it's set:

- Clients keep their old DNS until the DHCP lease renews. Reboot the device to
  force it, and verify from the device rather than from the router.
- Google TV honors DHCP DNS but silently falls back to `8.8.8.8` when the
  supplied resolver stops answering — a dead Pi-hole reads as "ads are back",
  not "internet is down".
- DoH/DoT bypasses DNS entirely: Firefox, iOS Private Relay, and Android's
  **Private DNS** setting. Switch Private DNS to Off on devices you care about.
- The real fix for hardcoded resolvers is a NAT redirect of outbound port 53 to
  Pi-hole. Consumer TP-Link firmware doesn't offer it; don't go looking.

If the DHCP DNS field genuinely isn't exposed, note that the usual workaround
does **not** apply here: "turn off the router's DHCP and let Pi-hole serve DHCP
instead" needs broadcast traffic and host networking, and Docker Desktop on
macOS has neither. While the host is a Mac, that route is closed. Fall back to
per-device DNS or Tailscale below, or put the ISP router in bridge mode behind
one you control.

### Tailscale (most robust, works outside the house)

1. Install Tailscale on the Pi-hole host and on the client devices.
2. In the Tailscale admin console → DNS, add the host's `100.x.x.x` address as a
   Global Nameserver and enable **Override local DNS**.

Every tailnet device then uses Pi-hole from anywhere, bypassing the router
entirely. Google TV and Android TV can run Tailscale natively; Samsung Tizen and
LG webOS cannot.

The host's tailnet node is **`pihole` = `100.74.173.13`** (this is the address in
the DNS console's Global Nameserver field). It's the Homebrew `tailscaled`
system daemon's node — see the pitfalls below.

**Run exactly one Tailscale install on the host.** This Mac had both the GUI
`Tailscale.app` (with its root network-extension) *and* the Homebrew
`tailscaled` system daemon. They can't cleanly share the tunnel, so one keeps
stopping — and when the host's node drops, every device with Override-local-DNS
loses *all* DNS, not just ad-blocking. Symptom on a client: raw IPs ping fine
(`ping 8.8.8.8` works) but names don't resolve (`ping google.com` →
"unknown host"). We standardized on the **Homebrew system daemon** because it
runs as root, survives reboot and logout, and needs no GUI session:

```sh
osascript -e 'tell application "Tailscale" to quit'   # stop the GUI app
sudo brew services restart tailscale                  # match daemon to CLI version
sudo tailscale up --accept-dns=false                  # log in; browser opens
tailscale set --accept-dns=false --hostname=pihole    # if 'up' flags don't stick
```

- **`--accept-dns=false` on the host is required.** The host runs Pi-hole; it
  must not accept the tailnet's "use Pi-hole for DNS" override, or it routes its
  own DNS through the tunnel back to itself. Verify with
  `tailscale debug prefs | grep CorpDNS` — want `false`.
- **Disable key expiry on the node** in the admin console (Machines → `pihole` →
  ⋯ → Disable key expiry). Node keys expire in ~180 days by default; when the
  key expires the node silently drops off the tailnet and takes DNS down for
  every Override-local-DNS client. This is the Tailscale equivalent of the
  disable-sleep step.
- **No automatic fallback, by design.** DNS dies when the host does, same
  tradeoff as the LAN setup. The manual escape hatch is to toggle Tailscale
  **off** on the client — it reverts to carrier/Wi-Fi DNS (ads return, but the
  internet works).

Debugging an Android client is fastest over `adb` (USB debugging on):
`adb shell settings get global private_dns_mode` (want `off`),
`adb shell ping -c1 <host-tailnet-ip>` (tunnel reachable?),
`adb shell ping -c1 google.com` (DNS resolving?).

## What this will and won't block

Blocks well: smart-TV OS telemetry, home-screen banner ads, ACR tracking, ads
inside free apps, and the usual web ads and trackers across phones and laptops.

**Does not block YouTube ads.** YouTube serves ads from `googlevideo.com`, the
same domain as the video itself, so no DNS-based blocker can separate them. The
same goes for in-stream ads on Netflix, Prime, and Hotstar.

If YouTube ads on the TV are the actual problem, the fix is **SmartTube**, an
open-source ad-free YouTube client sideloaded onto Android TV. It solves more of
that specific problem than this entire setup does.

## Operating it

```sh
docker compose logs -f      # what's it doing
docker compose restart      # after config changes
docker compose pull && docker compose up -d   # update
docker compose down         # stop (DNS dies for every device pointed here)
```

## Gotchas

- **Docker Desktop must open at login.** `restart: unless-stopped` only brings
  the container back if the Docker daemon comes back. Otherwise a reboot takes
  the network's DNS down until someone notices.
- **Per-client stats don't work.** Docker Desktop on macOS has no host
  networking, so every query appears to come from the bridge gateway. Blocking
  works fine; "which device is chatty" doesn't.
- **A DHCP address will eventually break everything.** If the host's IP moves,
  every device pointed at the old address loses DNS at once. `setup.sh` warns
  about this, but it can't fix it for you.
- **`.env` and `etc-pihole/` are gitignored.** The password and the query
  database stay on the machine.
