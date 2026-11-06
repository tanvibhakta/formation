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

## YouTube ReVanced (copied from Tanvi's Pixel 10)

Not scripted; these are the steps that worked on 2026-11-07.

1. Pull both APKs off the Pixel (`adb shell pm path <pkg>`, then `adb pull`):
   `app.revanced.android.gms` (GmsCore, install first) and `app.revanced.android.youtube`.
2. Install GmsCore with `adb install`. HyperOS shows an "Install this app via USB?" pop-up
   with a 7-second Deny countdown. Someone must tick **Remember my choice** and tap
   **Install**; later installs then go through silently.
3. Large APKs can stall over wireless `adb install`. Instead `adb push` the file to the
   phone, `cp` it into `/data/local/tmp/`, then run `adb shell pm install -r` on it. `pm install` can't
   read `/sdcard/...` directly (SELinux).
4. `adb shell dumpsys deviceidle whitelist +app.revanced.android.gms` so battery saver
   doesn't kill GmsCore (breaks sign-in and notifications).
5. Stock YouTube can't be disabled ("Cannot disable system packages"); `debloat.sh`
   removes it for user 0 instead.
6. On first launch ReVanced shows "Checks failed … patched on a different device". It
   stops after **Ignore** is pressed twice.

## What adb can't do on this phone

`input tap` fails with `INJECT_EVENTS` unless Developer options → "USB debugging
(Security settings)" is on, which needs a Mi account and a SIM with mobile data. So
pop-ups need a human tap. `input keyevent` (Back, Home) does work, a few seconds late.

## History

- 2026-11-06: first run removed 24 apps and disabled Screen Recorder; free space went from 161 GB to 164 GB.
- 2026-11-06: second batch removed 18 preinstalled ad/tracking/bloat apps, switched the
  keyboard to Gboard and disabled Facemoji; free space reached 172 GB.
- 2026-11-07: installed YouTube ReVanced + GmsCore, removed stock YouTube, removed 33
  background services rated "Recommended" by Universal Android Debloater (UAD-ng), and ran
  `pm trim-caches 999G`; free space reached 181 GB.
