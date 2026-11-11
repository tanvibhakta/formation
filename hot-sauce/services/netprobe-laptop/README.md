# Laptop network probe (second client)

The always-on Mac (`192.168.0.107`) runs `~/network-observability/netprobe.py`
every minute to investigate flaky home internet. Everything it sees is from
one machine, so it can't tell "the server's Wi-Fi is bad" from "the house's
Wi-Fi is bad". This runs the same probe on the laptop at the same time.

```sh
hot-sauce/services/netprobe-laptop/setup.sh
```

Differences from the server copy (see the comment at the top of `netprobe.py`):

- It pings the server across the LAN as well as the router.
- It queries Pi-hole at `192.168.0.107`, not at localhost or the container
  bridge, so it answers whether another device can reach Pi-hole.

Data: `~/network-observability/logs/netprobe.sqlite3` on the laptop, with the
same schema as the server's. It records only while the laptop is awake and at
home, so gaps are expected and are not outages.

Remove:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.tanvi.netprobe-laptop.plist
rm ~/Library/LaunchAgents/com.tanvi.netprobe-laptop.plist
```
