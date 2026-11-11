#!/usr/bin/env python3
"""
Lightweight network probe for home internet troubleshooting.
Writes one JSON object per run to ~/network-observability/logs/netprobe.jsonl.
Safe to run every 1-5 minutes. Uses only built-in macOS/Python tools.
"""
from __future__ import annotations

import json
import os
import platform
import re
import socket
import sqlite3
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path.home() / "network-observability"
LOG_DIR = ROOT / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
JSONL = LOG_DIR / "netprobe.jsonl"
DB = LOG_DIR / "netprobe.sqlite3"

# Laptop copy of the always-on Mac's netprobe.py, acting as a second client.
# Differences from the server copy: it also pings the server across the LAN, and it
# queries Pi-hole at the server's LAN address instead of localhost/container addresses,
# so it shows whether another device can reach Pi-hole while the server can.
SERVER_LAN = "192.168.0.107"
TARGETS = {
    "gateway": None,          # filled from route
    "server": SERVER_LAN,
    "cloudflare": "1.1.1.1",
    "google_dns": "8.8.8.8",
}
DNS_NAMES = ["google.com", "cloudflare.com", "actcorp.in"]
DNS_SERVERS = {
    "pihole_lan": SERVER_LAN,
    "cloudflare_direct": "1.1.1.1",
    "google_direct": "8.8.8.8",
}
HTTP_URLS = [
    "https://www.gstatic.com/generate_204",
    "https://www.google.com/generate_204",
]


def run(cmd: list[str], timeout: int = 10) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except Exception as e:
        return 999, repr(e)


def default_gateway() -> tuple[str | None, str | None]:
    code, out = run(["route", "-n", "get", "default"], timeout=5)
    gw = iface = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("gateway:"):
            gw = line.split(None, 1)[1]
        elif line.startswith("interface:"):
            iface = line.split(None, 1)[1]
    return gw, iface


def ping_stats(host: str, count: int = 10) -> dict:
    code, out = run(["ping", "-c", str(count), "-i", "0.2", "-W", "1000", host], timeout=count + 5)
    result = {"host": host, "ok": code == 0, "loss_pct": None, "min_ms": None, "avg_ms": None, "max_ms": None, "stddev_ms": None}
    m = re.search(r"(\d+(?:\.\d+)?)% packet loss", out)
    if m:
        result["loss_pct"] = float(m.group(1))
    m = re.search(r"round-trip .* = ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+) ms", out)
    if m:
        result.update({"min_ms": float(m.group(1)), "avg_ms": float(m.group(2)), "max_ms": float(m.group(3)), "stddev_ms": float(m.group(4))})
    if code != 0:
        result["error"] = out[-500:]
    return result


def dns_timing(name: str) -> dict:
    t0 = time.perf_counter()
    try:
        addrs = socket.getaddrinfo(name, 443, proto=socket.IPPROTO_TCP)
        ms = (time.perf_counter() - t0) * 1000
        ips = sorted({a[4][0] for a in addrs})[:5]
        return {"name": name, "ok": True, "ms": round(ms, 2), "ips": ips}
    except Exception as e:
        return {"name": name, "ok": False, "ms": round((time.perf_counter() - t0) * 1000, 2), "error": repr(e)}


def direct_dns_timing(server_name: str, server: str, name: str = "google.com") -> dict:
    """Time a DNS query against a specific server, bypassing the macOS system resolver."""
    t0 = time.perf_counter()
    code, out = run(["dig", "+time=2", "+tries=1", "+stats", "+short", f"@{server}", name, "A"], timeout=5)
    ms = (time.perf_counter() - t0) * 1000
    ips = [line.strip() for line in out.splitlines() if re.match(r"^\d+\.\d+\.\d+\.\d+$", line.strip())]
    result = {"server_name": server_name, "server": server, "name": name, "ok": code == 0 and bool(ips), "ms": round(ms, 2), "ips": ips[:5]}
    if not result["ok"]:
        result["error"] = out[-500:]
    return result


def wifi_info() -> dict:
    """Capture current Wi-Fi PHY/channel/rate/RSSI from macOS System Profiler."""
    code, out = run(["system_profiler", "SPAirPortDataType"], timeout=20)
    info = {"ok": code == 0}
    if code != 0:
        info["error"] = out[-500:]
        return info
    current = False
    for raw in out.splitlines():
        line = raw.strip()
        if line == "Current Network Information:":
            current = True
            continue
        if current and line == "Other Local Wi-Fi Networks:":
            break
        if not current:
            continue
        if line.endswith(":") and not line.startswith(("PHY Mode", "Channel", "Country Code", "Network Type", "Security", "Signal", "Transmit", "MCS")):
            info["ssid"] = line[:-1]
        elif line.startswith("PHY Mode:"):
            info["phy_mode"] = line.split(":", 1)[1].strip()
        elif line.startswith("Channel:"):
            info["channel"] = line.split(":", 1)[1].strip()
            m = re.search(r"(\d+)GHz", line)
            if m:
                info["band_ghz"] = int(m.group(1))
            m = re.search(r"(\d+)MHz", line)
            if m:
                info["channel_width_mhz"] = int(m.group(1))
        elif line.startswith("Signal / Noise:"):
            m = re.search(r"(-?\d+) dBm / (-?\d+) dBm", line)
            if m:
                info["signal_dbm"] = int(m.group(1))
                info["noise_dbm"] = int(m.group(2))
                info["snr_db"] = int(m.group(1)) - int(m.group(2))
        elif line.startswith("Transmit Rate:"):
            try:
                info["tx_rate_mbps"] = float(line.split(":", 1)[1].strip())
            except ValueError:
                pass
        elif line.startswith("MCS Index:"):
            info["mcs_index"] = line.split(":", 1)[1].strip()
    return info


def http_timing(url: str) -> dict:
    t0 = time.perf_counter()
    try:
        req = urllib.request.Request(url, method="GET", headers={"User-Agent": "netprobe/1.0"})
        with urllib.request.urlopen(req, timeout=8) as r:
            r.read(128)
            ms = (time.perf_counter() - t0) * 1000
            return {"url": url, "ok": True, "status": r.status, "ms": round(ms, 2)}
    except Exception as e:
        return {"url": url, "ok": False, "ms": round((time.perf_counter() - t0) * 1000, 2), "error": repr(e)}


def snapshot() -> dict:
    gw, iface = default_gateway()
    targets = dict(TARGETS)
    targets["gateway"] = gw
    record = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "host": socket.gethostname(),
        "os": platform.platform(),
        "gateway": gw,
        "interface": iface,
        "wifi": wifi_info(),
        "pings": {name: ping_stats(ip) for name, ip in targets.items() if ip},
        "dns": [dns_timing(n) for n in DNS_NAMES],
        "dns_direct": [direct_dns_timing(n, s) for n, s in DNS_SERVERS.items()],
        "http": [http_timing(u) for u in HTTP_URLS],
    }
    # If something is clearly broken, capture a short traceroute for later forensics.
    bad = any((p.get("loss_pct") or 0) > 0 or (p.get("avg_ms") or 0) > 200 for p in record["pings"].values())
    if bad:
        code, out = run(["traceroute", "-m", "8", "-q", "1", "-w", "2", "1.1.1.1"], timeout=25)
        record["traceroute_1_1_1_1"] = out[-2000:]
    return record


def init_db(conn: sqlite3.Connection) -> None:
    conn.execute("""
    create table if not exists probe_runs (
        ts text primary key,
        gateway text,
        interface text,
        gateway_loss real,
        gateway_avg_ms real,
        cloudflare_loss real,
        cloudflare_avg_ms real,
        google_dns_loss real,
        google_dns_avg_ms real,
        dns_google_ms real,
        http_gstatic_ms real,
        raw_json text not null
    )
    """)


def write(record: dict) -> None:
    with JSONL.open("a") as f:
        f.write(json.dumps(record, separators=(",", ":")) + "\n")
    with sqlite3.connect(DB) as conn:
        init_db(conn)
        p = record.get("pings", {})
        dns_google = next((d for d in record.get("dns", []) if d.get("name") == "google.com"), {})
        http_gstatic = next((h for h in record.get("http", []) if "gstatic" in h.get("url", "")), {})
        conn.execute(
            "insert or replace into probe_runs values (?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                record["ts"], record.get("gateway"), record.get("interface"),
                p.get("gateway", {}).get("loss_pct"), p.get("gateway", {}).get("avg_ms"),
                p.get("cloudflare", {}).get("loss_pct"), p.get("cloudflare", {}).get("avg_ms"),
                p.get("google_dns", {}).get("loss_pct"), p.get("google_dns", {}).get("avg_ms"),
                dns_google.get("ms"), http_gstatic.get("ms"), json.dumps(record),
            ),
        )


def main() -> None:
    rec = snapshot()
    write(rec)
    print(json.dumps(rec, indent=2))

if __name__ == "__main__":
    main()
