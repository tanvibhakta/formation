# Firefox for Android → Kagi

Makes Kagi the default search engine in Firefox on the Pixel, including search
suggestions, authenticating by session token rather than by cookie.

Not wired into `hot-sauce/setup.sh` — it provisions a phone, not this Mac, and
it needs that phone awake, unlocked, and reachable over adb.

## Setup

Turn on wireless debugging on the phone and pair it, then:

```sh
cd hot-sauce/services/firefox-android-kagi
./setup.sh
```

The script is idempotent. Re-running it edits the existing Kagi engine instead
of adding a second one, which is also how you refresh the token after logging
out of Kagi. It verifies the result with a real search before claiming success.

Prerequisite it cannot do for you: **Firefox on the phone must already be signed
in to Kagi.** The script reads the session link out of Kagi's own settings page,
so there has to be a session to read. It stops with a clear message if not.

## Why UI automation

Firefox for Android has no settings API and no config file for this. Custom
search engines live inside the app's private data directory, so on an unrooted
phone the only way in is the settings UI. The script drives it over
`adb shell input`, resolving every element from a live `uiautomator` dump by
resource id or label — never a hardcoded coordinate, so a layout change fails
loudly instead of tapping the wrong row.

One shortcut worth knowing: `am start -d fenix://settings_search_engine` jumps
straight to Firefox's search settings and skips the whole menu walk.

## The traps

### `adb shell input text` is not a faithful typist

It routes through the IME, and Gboard rewrites what it receives:

| You send | Gboard commits |
|---|---|
| `kagi.com` | `kagi. com` |
| `/autosuggest` | `/Autosuggest` |
| `%s` | a space |

That last one is the dangerous one. `%s` is the query placeholder, so losing it
produces a search engine that looks configured and silently searches for
nothing. None of the three raise an error.

Injecting raw key codes (`lib/type_keys.py`) fixes `%s`, but auto-space and
auto-capitalise still apply. **`KEYCODE_PASTE` is the only input path that lands
text byte-for-byte**, which is why both URLs arrive via the clipboard and the
script only ever *types* the engine name.

Where typing is unavoidable — splicing `/search` into `/api/autosuggest` — the
workaround is a throwaway `x` in front of each path segment. Gboard capitalises
the guard, the guard gets deleted, and the real character survives in lower
case.

### Token, not cookie

Signing in leaves a session cookie, and a plain `https://kagi.com/search?q=%s`
rides on it. That works right up until cookies get cleared, at which point every
search silently bounces to a sign-in page.

Kagi's Settings → User Details renders a ready-made
`https://kagi.com/search?token=…&q=%s` with a **Copy to Clipboard** button. That
URL carries its own authentication, so it survives a cookie wipe.

This is also why no secret is stored in this repo: the script taps Kagi's own
copy button and pastes device-side, so the token never reaches this machine and
there is nothing here to gitignore. It invalidates when you log out of Kagi —
re-run the script to pick up a fresh one.

### Verify in a private tab

A normal-window search proves nothing while a valid cookie exists — it would
succeed even with a broken token. A private tab has a separate cookie jar and is
not signed in, so a Kagi results page there is proof the token authenticates on
its own. That is the check the script ends on.

### The screen going to sleep looks like something else

If the display blanks mid-run, every subsequent tap misses and
`dumpsys window` keeps reporting `NotificationShade` as focused, which reads
like a stuck system UI rather than a timeout. The script raises
`screen_off_timeout` for the duration and restores it on exit.

## Files

| File | Purpose |
|---|---|
| `setup.sh` | The whole flow: preflight, token, engine, verify |
| `lib/ui.py` | Finds elements by id or label in a `uiautomator` dump; masks anything token-shaped in its debug output |
| `lib/type_keys.py` | Types via raw key codes, for the few strings that cannot be pasted |

`python3 lib/ui.py dump` prints the current screen with tap coordinates, which
is the fastest way to adapt this after a Fenix redesign.
