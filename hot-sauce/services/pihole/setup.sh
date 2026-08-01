#!/usr/bin/env bash

###############################################################################
# PI-HOLE SETUP
#
# Deliberately NOT called by hot-sauce/setup.sh. Exactly one machine on the LAN
# should run a DNS server, and running this on a laptop that leaves the house
# would take the network's DNS with it. Run it by hand, on the always-on box.
#
# Safe to run repeatedly — every step checks before it acts.
###############################################################################

set -e

PIHOLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same fallback helpers as hot-sauce/setup.sh, so this can run standalone.
if type print_success &>/dev/null; then
    HAS_HELPERS=true
else
    HAS_HELPERS=false
    print_success() { printf "  [✓] $1\n"; }
    print_success_muted() { printf "  [✓] $1 (skipped)\n"; }
    print_warning() { printf "  [!] $1\n"; }
    print_error() { printf "  [✗] $1\n"; }
    ask() {
        local prompt default reply
        if [ "${2:-}" = "Y" ]; then prompt="Y/n"; default=Y;
        elif [ "${2:-}" = "N" ]; then prompt="y/N"; default=N;
        else prompt="y/n"; default=; fi
        echo -n "  [?] $1 [$prompt] "
        read reply </dev/tty
        [ -z "$reply" ] && reply=$default
        case "$reply" in Y*|y*) return 0 ;; *) return 1 ;; esac
    }
fi

###############################################################################
# DOCKER
###############################################################################
echo ""
echo "  ── Docker ──"
if ! command -v docker &>/dev/null; then
    print_error "Docker not found. Install Docker Desktop first."
    exit 1
fi

if ! docker info &>/dev/null; then
    print_error "Docker daemon isn't running. Start Docker Desktop and re-run."
    exit 1
fi
print_success "Docker is running"

# restart: unless-stopped only helps if Docker Desktop itself comes back on
# login. There's no reliable CLI for that setting, so this is a nag, not a fix.
print_warning "Check Docker Desktop → Settings → General → 'Start Docker Desktop when you sign in'"

###############################################################################
# PORT 53
# Pi-hole can't bind 53 if something else holds it. mDNSResponder uses 5353 and
# is not a conflict; a previous Pi-hole, dnsmasq or unbound would be.
###############################################################################
echo ""
echo "  ── Port 53 ──"
if docker ps --format '{{.Names}}' | grep -qx pihole; then
    print_success_muted "pihole container already running; skipping port check"
else
    # sudo -n so this never blocks on a password prompt; without it lsof can
    # miss root-owned listeners, hence the fallback and the softened wording.
    PORT53="$(sudo -n lsof -nP -iUDP:53 2>/dev/null || lsof -nP -iUDP:53 2>/dev/null || true)"
    if [ -n "$PORT53" ]; then
        print_error "Something is already listening on UDP 53:"
        echo "$PORT53" | sed 's/^/      /'
        print_error "Stop it before starting Pi-hole."
        exit 1
    fi
    print_success "UDP 53 is free"
fi

###############################################################################
# LAN ADDRESS
# Every device that uses this Pi-hole hardcodes its IP. If the address moves,
# DNS breaks everywhere at once — so it has to be manually configured, not DHCP.
###############################################################################
echo ""
echo "  ── LAN address ──"
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"

if [ -z "$LAN_IP" ]; then
    print_warning "Couldn't determine a LAN IP — check you're on Wi-Fi or Ethernet"
else
    print_success "This machine is $LAN_IP"
    SERVICE="$(networksetup -listallnetworkservices 2>/dev/null | grep -i "wi-fi" | head -1 || true)"
    if [ -n "$SERVICE" ]; then
        if networksetup -getinfo "$SERVICE" 2>/dev/null | grep -q "Manual Configuration"; then
            print_success "$SERVICE uses a manual IP — good, it won't move"
        else
            print_warning "$SERVICE is on DHCP. Set a manual IP before pointing devices here:"
            print_warning "  System Settings → Network → $SERVICE → Details → TCP/IP"
            print_warning "  → Configure IPv4: 'Using DHCP with manual address'"
        fi
    fi
fi

###############################################################################
# SLEEP
# The single most common way a self-hosted Pi-hole dies: the host sleeps and
# every device on the network quietly loses DNS.
###############################################################################
echo ""
echo "  ── Sleep ──"
SLEEP_VAL="$(pmset -g 2>/dev/null | awk '$1 == "sleep" { print $2 }' || true)"
if [ "$SLEEP_VAL" = "0" ]; then
    print_success "System sleep is already disabled"
else
    print_warning "System sleep is enabled (sleep = ${SLEEP_VAL:-unknown})"
    if ask "Disable sleep so DNS stays up? (needs sudo)" Y; then
        sudo pmset -a sleep 0 disablesleep 1
        print_success "Sleep disabled"
        print_warning "Keep the lid open, or run clamshell with power + an external display"
    else
        print_success_muted "Sleep left as-is — expect DNS outages when this Mac naps"
    fi
fi

###############################################################################
# PASSWORD
###############################################################################
echo ""
echo "  ── Admin password ──"
if [ -f "$PIHOLE_DIR/.env" ]; then
    print_success_muted ".env already exists"
else
    GENERATED="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
    printf 'PIHOLE_PASSWORD=%s\n' "$GENERATED" > "$PIHOLE_DIR/.env"
    chmod 600 "$PIHOLE_DIR/.env"
    print_success "Generated .env with a random admin password"
    print_warning "Password: $GENERATED"
    print_warning "Save it to 1Password now — it's shown here once and .env is gitignored"
fi

###############################################################################
# START
###############################################################################
echo ""
echo "  ── Starting Pi-hole ──"
cd "$PIHOLE_DIR"
docker compose up -d
print_success "Pi-hole is up"

###############################################################################
# VERIFY
# Prove it actually resolves before trusting the whole house to it.
###############################################################################
echo ""
echo "  ── Verifying ──"
for _ in $(seq 1 15); do
    if dig +short +time=1 +tries=1 @127.0.0.1 example.com &>/dev/null; then
        break
    fi
    sleep 1
done

if dig +short +time=2 +tries=1 @127.0.0.1 example.com | grep -qE '^[0-9]+\.'; then
    print_success "Resolves through Pi-hole"
else
    print_error "Pi-hole isn't answering on 127.0.0.1:53 — check: docker compose logs"
    exit 1
fi

# doubleclick.net is on every default blocklist; 0.0.0.0 means blocking works.
BLOCKED="$(dig +short +time=2 +tries=1 @127.0.0.1 doubleclick.net || true)"
if [ "$BLOCKED" = "0.0.0.0" ] || [ -z "$BLOCKED" ]; then
    print_success "Ad domains are being blocked"
else
    print_warning "doubleclick.net resolved to $BLOCKED — blocklists may still be loading"
fi

###############################################################################
# DONE
###############################################################################
echo ""
print_success "Pi-hole ready 🕳️"
echo ""
echo "  Admin UI:  http://${LAN_IP:-localhost}:8080/admin"
echo "  DNS:       ${LAN_IP:-<this machine>}"
echo ""
echo "  Next: point devices at it. See README.md — and note that the"
echo "  secondary DNS must be this same IP, never 1.1.1.1."
echo ""
