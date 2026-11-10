# Android: links open in Firefox, not inside apps

Goal: tapping a link in any app opens full Firefox, the default browser, not a
browser view inside that app. Set up on the Pixel 10 on 2026-10-13.

Run `./setup.sh` with the phone on USB. It disables Chrome, checks the default
browser and prints the per-app checklist below. The per-app switches have to
be flipped by hand.

## Why there is no single switch

"In-app browser" covers two mechanisms:

- **Custom Tab.** The app asks a browser app (Chrome or Firefox) to draw the
  page inside the app's window. It shares the browser's cookies and logins,
  and the toolbar menu has "Open in Firefox". Android picks the browser.
- **WebView.** The app embeds its own browser engine and controls it fully.
  No system setting reaches it.

Either way, the only real fix is the app's own setting, which makes it send a
plain link to Android so Android opens the default browser.

## What adb can and can't do

- `pm disable-user com.android.chrome` works without root. Apps that hard-code
  Chrome as their Custom Tab browser then use Firefox instead. Re-enable with
  `adb shell pm enable com.android.chrome`.
- Disabling Firefox's Custom Tabs service was the plan for a global fix:
  with no provider left, apps would have to fall back to a plain link. Android
  refuses that without root:
  `SecurityException: Shell cannot change component state for ComponentInfo{org.mozilla.firefox/org.mozilla.fenix.customtabs.CustomTabsService}`.
  So Firefox remains a provider, and the per-app settings are required.

## Per-app settings

| App | Path | Value | Status |
|---|---|---|---|
| Slack | You (avatar) → Preferences → Device & troubleshooting → Open web pages in app | OFF | done |
| Telegram | Settings → Chat Settings → In-App Browser. **Tap the label, not the switch**, to open the "Web Browser" page | Enable In-App Browser: OFF, **Windowed Mode: OFF** | done |
| Inoreader | Drawer → scroll to bottom → Settings → Miscellaneous → Browser | External | done |
| Discord | Server list → avatar (bottom left) → Settings → Web Browser | External Browser | done |
| Raindrop | Gear → Open in browser | System default | done |
| Gmail | Drawer → Settings → General settings → Open web links in Gmail | OFF | already off |
| Google app | Avatar → Settings → Other settings → Open web pages in the app | OFF | greyed out while Chrome is disabled |
| YouTube (ReVanced) | You → gear → ReVanced Settings → Miscellaneous → Open links in browser | ON | already on |
| Reddit | | | not done: a blocker app closes it on launch |
| X (piko) | | | not done: a blocker app closes it on launch |
| Beeper | | | not done: logged out |
| Mastodon | | | not done: logged out |
| Facebook | Settings & privacy → Settings → Media → Links open externally (unverified path) | ON | not done: logged out |

No setting exists, checked: WhatsApp (settings search finds nothing; it
already opens the browser), Todoist (nothing under General).

## Traps

- **Telegram's "In-App Browser" switch is not the whole story.** It was already
  OFF, but links still opened in a Firefox Custom Tab. The cause is "Windowed
  Mode" ("Open external browser inside of Telegram") on the sub-page behind
  the label.
- **The Google app's switch depends on Chrome.** While Chrome is disabled it
  reads ON but is greyed out ("Install the latest version of Chrome to
  enable") and inactive. If Chrome is ever re-enabled, turn it off there.
- **Inoreader with "Open webpages directly" ON** (Miscellaneous) now sends
  every article straight to Firefox, skipping the RSS summary.
- `uiautomator dump` includes views hidden behind the front screen (Slack's
  split home/channel layout), so a tap aimed at a dumped node can land on
  something else. Check with a screenshot when a tap does nothing.
- A tap sent while a list is still scrolling stops the scroll and doesn't
  toggle anything. Wait and re-check the switch state.
- Autoplaying video (YouTube home) makes `uiautomator dump` fail with
  "could not get idle state". Navigate by screenshot there.
