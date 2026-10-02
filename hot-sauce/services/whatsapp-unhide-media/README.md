# WhatsApp → unhide downloaded media

Makes every file WhatsApp has downloaded onto the Pixel visible to other apps:
Files by Google, Moon+ Reader, the gallery. Without this, an epub someone sent
you on WhatsApp can sit on the phone and still be invisible to every reader
app you own.

Not wired into `hot-sauce/setup.sh` — it provisions a phone, not this Mac, and
it needs that phone reachable over adb. It does not need the screen unlocked.

## Setup

Turn on wireless debugging on the phone and pair it, then:

```sh
cd hot-sauce/services/whatsapp-unhide-media
./setup.sh
```

The script is idempotent. It re-checks each folder, removes any marker WhatsApp
has put back, rescans, and compares the indexer's row count against the files
on disk before claiming success.

## Why the files were hidden

WhatsApp keeps received files under its own app folder:

```
Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents/
```

Files it wants to keep out of your gallery go one level deeper, into a
`Private/` subfolder alongside a `.nomedia` marker. Android's media indexer
(MediaProvider) honours that marker: it records the files but classifies them
as `media_type = 0`, "none", and every app that browses by category rather
than by walking the disk filters those rows out. Files by Google, Moon+ Reader
and the gallery all work that way, so the file is on the phone but appears
nowhere.

WhatsApp routes files into `Private/` in two cases:

1. **The Media visibility switch is off** (Settings → Chats → Media
   visibility), or the per-chat override is set to "No" (chat → contact name →
   Media visibility).
2. **The chat has disappearing messages on.** This one ignores the switch
   entirely; WhatsApp does it so short-lived media never lands in the gallery.

On this phone the global switch was already on. The hidden files came from
case 2, so flipping a setting would have changed nothing.

## Why remove the marker rather than move the files

WhatsApp's message database stores the path of every attachment. Move a file
out of `Private/` and the chat bubble it belongs to turns into a "download
again" placeholder. Deleting the marker and rescanning leaves every path
intact, so WhatsApp keeps working and the rest of the phone gains access.

## The traps

- **Deleting `.nomedia` is not enough.** Existing rows keep `media_type = 0`
  until the folder is rescanned. The script does that with the indexer's own
  `scan_file` method via `content call`, which works from the adb shell and
  handles a whole folder in one call. The older `MEDIA_SCANNER_SCAN_FILE`
  broadcast reports success from the shell, but it was not tested on its own,
  so the script does not rely on it.
- **A blanket `find /sdcard -iname` from the adb shell returns nothing** for
  this tree, even though `ls` on the same folder works. Point `find` at
  `/sdcard/Android/media` explicitly.
- **Expect WhatsApp to put the marker back** at some point, most likely the
  next time a disappearing-message chat receives media. New files after that
  go back to being invisible. Re-run the script; that is the whole reason it
  is idempotent. (Not yet observed; the marker was still absent twenty minutes
  after removal with the disappearing-message chat active.)
- **Do not touch the other `.nomedia` markers** under `Sent/`, `Voice Notes/`,
  `Stickers/` and the dot-folders. Those are WhatsApp's working directories,
  not things you want in your gallery.
- **The count check allows a gap of five.** A few files with unrecognised
  extensions or zero bytes legitimately stay unclassified. A larger gap means
  the rescan did not take.

## Related

Moon+ Reader's history and shelf live in its private app data, which the Pixel
phone-to-phone transfer did not carry over. That is separate from this: turn
on Moon+'s own backup (Options → Misc) so the shelf survives the next move.
