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

Admin UI lands on `http://<host-ip>:8080/admin` — 8080 rather than 80 so nginx
and local dev servers keep working.

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

Network → your Wi-Fi → IP settings → Static. Set both DNS fields to the host IP.

### Router (all devices at once) — try this first

`Advanced → Network → DHCP Server → Primary/Secondary DNS` — **not** the WAN
DNS page under Internet. WAN DNS only changes what the router itself resolves
against; it never reaches clients. An earlier attempt at this setup burned a
day on WAN DNS, static WAN IP, and Dynamic DNS without ever opening the DHCP
page, so start here.

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
