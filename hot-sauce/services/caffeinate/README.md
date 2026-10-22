# Caffeinate

Keep the laptop awake while it's plugged in, plus a manual Alfred toggle for
when it's on battery.

```sh
cd hot-sauce/services/caffeinate
./setup.sh
```

The script is idempotent. It asks for your password once, the first time it
runs `pmset`.

## What it does

**On charger: `sudo pmset -c sleep 0`.** `-c` means "charger": it edits only
the AC Power profile. The Mac never idle-sleeps while plugged in, and on
battery it still sleeps on its usual timer. Check with `pmset -g custom`.

There's no Alfred workflow, or `caffeinate` flag, that switches itself on and
off with the charger. `caffeinate -s` comes close, since it only holds the Mac
awake on AC power, but it has to stay running and dies at logout. The pmset
profile is the setting macOS itself checks, so it survives reboots and needs
nothing running.

Display sleep is set separately, to `0` for all power sources, in
`hot-sauce/macos-defaults.sh`.

**On battery: Caffeine Dose workflow.** This is
[vanstrouble/caffeine-dose-alfred-workflow](https://github.com/vanstrouble/caffeine-dose-alfred-workflow),
the caffeinate workflow on the Alfred Gallery. ("Caffeinate Control" isn't on
the Gallery.)

| Keyword       | Effect                               |
|---------------|--------------------------------------|
| `caff`        | toggle awake on/off                  |
| `cfs 2h`      | awake for 2 hours                    |
| `cfs 9:30pm`  | awake until 9:30 PM                  |
| `cfs s` / `d` | status / deactivate                  |

Hold ⌘ with either keyword to let the display sleep.

## Traps

- **Closing the lid still sleeps the Mac**, even on charger, unless an
  external display is connected (clamshell mode). `pmset` idle sleep doesn't
  cover the lid.
- **Caffeine Dose runs `pkill -x caffeinate`** when it starts or stops. That
  kills *every* `caffeinate` process, including ones other tools started.
- **Alfred's live sync folder is `~/Dropbox/Alfred preferences`**, not the
  `hot-sauce/alfred` copy that `setup.sh` points it at. The script reads
  whichever folder Alfred is actually using, so it won't install the workflow
  twice.
