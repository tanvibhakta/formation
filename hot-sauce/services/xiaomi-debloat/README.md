# xiaomi-debloat

Removes apps Mom doesn't want from her Xiaomi (model `24053PY09I`, codename
`chenfeng`, HyperOS). The app list and what was deliberately kept live at the top
of `debloat.sh`.

## Run

1. On the phone: Developer options → Wireless debugging on (USB debugging also works).
2. Connect from the Mac:
   ```sh
   adb mdns services                # find the phone's _adb-tls-connect address
   adb connect <ip>:<port>          # port changes after every reboot
   ```
3. `./debloat.sh` (auto-picks the Xiaomi) or `./debloat.sh <adb-serial>`.

Safe to re-run: anything already gone is skipped.

## How each app is removed

The script tries three steps in turn and stops at the first that works:

| Step | Command | Undo |
|---|---|---|
| Uninstall (apps someone installed; skipped for preinstalled apps, where it only strips updates yet still reports `Success`) | `pm uninstall <pkg>` | Reinstall from Play Store |
| Remove for user 0 (preinstalled apps) | `pm uninstall -k --user 0 <pkg>` | `adb shell cmd package install-existing <pkg>` |
| Disable (HyperOS blocks uninstall with `Failure [-1000]`) | `pm disable-user --user 0 <pkg>` | `adb shell pm enable <pkg>` |

A factory reset brings back every preinstalled app.

Facemoji (`com.preff.kb.xm`) is her default keyboard, so the script switches the
keyboard to Gboard first and stops if that fails.

## History

- 2026-11-06: first run removed 24 apps and disabled Screen Recorder; free space went from 161 GB to 164 GB.
- 2026-11-06: second batch removed 18 preinstalled ad/tracking/bloat apps, switched the
  keyboard to Gboard and disabled Facemoji; free space reached 172 GB.
