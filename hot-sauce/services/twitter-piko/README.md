# Twitter (piko)

The official X Android app, patched with [piko](https://github.com/crimera/piko)
so it has no ads and is called **Twitter** with the bird icon again.

```sh
./setup.sh                      # prints which X version to download
./setup.sh ~/Downloads/com.twitter.android_<version>-*.apkm
```

Re-run it whenever you want to update. It always uses the latest stable piko
release and works out which X version that release needs.

## What it does

1. Installs Java (Homebrew `openjdk`) and fetches the latest stable
   [Morphe desktop](https://github.com/MorpheApp/morphe-desktop) and piko releases.
2. Reads the one X version that piko release supports.
3. Patches the X bundle you downloaded. "Remove Ads" is on by default.
   "Bring back twitter" is **off by default**, so the script turns it on by name.
4. Installs the result over adb, uninstalling the Play Store X first if
   needed (it asks before doing that).

## Instagram

piko patches Instagram too. `setup.sh` doesn't handle it yet. This is what
was run on 2026-10-13 (Instagram 447.0.0.55.81, arm64 bundle with version code
385311895, the exact build piko lists):

```sh
java -jar morphe-desktop-*-all.jar patch --patches=patches-*.mpp --exclusive \
  -e "Disable ads" -e "Hide suggested content" \
  -e "Limit feed to following profiles" -e "Disable discover people" \
  -e "Add settings" -e "Change version code" -e "Open links externally" \
  --keystore=~/.config/twitter-piko/twitter-piko.keystore \
  -o instagram-piko.apk com.instagram.android_*.apkm
```

`--exclusive` matters. piko turns on ~50 Instagram patches by default,
including *Disable comments*, *Disable stories* and *Disable explore*.
"Disable ads" covers feed and story ads together; there's no per-placement
option. "Hide suggested content" still shows suggested *posts*, which is why
"Limit feed to following profiles" is on as well. "Change version code" sets
the version code to the maximum, so the Play Store never offers an update over it.
"Open links externally" sends links to the default browser or app instead of
Instagram's in-app browser.

Instagram is signed with the **same keystore** as Twitter, so the one
1Password item covers both apps.

## Traps

- **APKMirror blocks scripts (HTTP 403).** Download the `.apkm` in a browser.
  Get the exact version piko lists. A newer X is not "close enough", because
  the patches look for specific code in that one build.
- **The signing key is in 1Password** (Private vault, "Twitter piko signing
  keystore"), with a working copy at `~/.config/twitter-piko/twitter-piko.keystore`.
  Android only installs an update over an app signed with the same key. Without
  it, the next update means uninstalling and logging in again. The script pulls
  it from 1Password when the local copy is missing, and backs up a newly
  generated one. It's a private key, so it never goes in this repo.
- **The first install logs you out.** The Play Store X is signed by X Corp, so
  Android won't install our build over it. It has to be uninstalled first.
- **Turn off auto-update for X in the Play Store** (X page → ⋮ → untick
  *Enable auto update*). Otherwise Play may replace the patched app.
- **Morphe needs Java 21+.** `dotfiles/zshrc` pins the shell to Java 17, so
  the script calls `/opt/homebrew/opt/openjdk/bin/java` by full path instead
  of changing the global Java.
- **"USB debugging" and "Wireless debugging" are separate switches** in
  Developer options. If the Mac shows the phone in System Information but
  `adb devices` is empty, USB debugging is off.
- **Wireless debugging over the phone's own hotspot isn't found
  automatically.** adb's mDNS discovery returns nothing on the Pixel's hotspot.
  Use a cable, or `adb connect <ip:port>` from the Wireless debugging screen.
