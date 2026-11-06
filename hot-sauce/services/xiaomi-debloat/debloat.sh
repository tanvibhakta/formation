#!/usr/bin/env bash
# Remove unwanted apps from Mom's Xiaomi (24053PY09I, "chenfeng").
# Re-runnable: apps already gone are reported and skipped.
#
# Usage: ./debloat.sh [adb-serial]
#   adb-serial defaults to the first device whose model is 24053PY09I.
#
# User-installed apps are uninstalled outright. Preinstalled apps can't be
# uninstalled, so they are removed for user 0 only ("pm uninstall --user 0");
# restore one with:  adb shell cmd package install-existing <package>
set -euo pipefail

MODEL=24053PY09I

# Kept on purpose (decided 2026-11-06): Rapido, the remaining banking and
# government apps (DigiLocker, MyGov, MyGrievance, BMTC, Airtel), and the
# devotional/unidentified apps.
REMOVE=(
  # Not opened in over a year
  com.ubercab                                    # Uber
  com.olacabs.customer                           # Ola
  com.olx.southasia                              # OLX
  flipboard.boxer.app                            # Flipboard
  com.microsoft.teams                            # Microsoft Teams
  com.microsoft.skydrive                         # OneDrive
  com.google.android.apps.meetings               # Google Meet (old app)
  com.google.android.music                       # Google Play Music (dead service)
  com.sec.kidsplat.kidsgallery                   # Samsung Kids Gallery (from old phone)
  com.sec.spp.push                               # Samsung Push (from old phone)
  cn.wps.xiaomi.abroad.lite                      # WPS Office Lite
  com.duokan.phone.remotecontroller              # Mi Remote
  com.xiaomi.smarthome                           # Mi Home
  com.miui.screenrecorder                        # Screen Recorder
  com.miui.mediaeditor                           # Mi Video Editor
  com.freevoicetranslator.languagetranslate.speakandtranslate  # Voice translator
  com.religare                                   # Religare
  com.disprz.hdfclife                            # HDFC Life (Disprz learning)
  com.hdfcclife.activities                       # HDFC Life
  com.hdfclife.msdSSO                            # HDFC Life SSO
  # PDF / Word readers (Files by Google and Drive open these)
  com.koishd.pdf.viewer
  com.pdffile.reader.pdffr
  com.pdfreader.pdfviewer.fastpdfreader.pdf
  com.mese.documents.proreader.docs.pdf.viewer
  word.office.docxviewer.document.docx.reader
  # Preinstalled bloat, ads and tracking (approved 2026-11-06)
  com.miui.msa.global                            # MSA, Xiaomi ad service
  com.miui.analytics                             # Xiaomi analytics
  com.facebook.services                          # Facebook background services
  com.facebook.appmanager                        #   (the Facebook app itself stays)
  com.facebook.system
  com.xiaomi.mipicks                             # GetApps store
  com.indus.appstore                             # Indus App Store
  com.xiaomi.glgm                                # Xiaomi Games
  com.google.android.apps.subscriptions.red      # Google One
  com.google.android.videos                      # Play Movies
  com.google.android.apps.youtube.music          # YouTube Music
  com.mi.globalminusscreen                       # App Vault (swipe-left screen)
  com.miui.player                                # Mi Music
  com.mi.global.shop                             # Mi Store
  com.miui.miservice                             # Services & Feedback
  com.miui.bugreport                             # Bug Report
  com.netflix.mediaclient                        # Netflix
  com.miui.android.fashiongallery                # Glance lock-screen wallpapers/ads
  com.preff.kb.xm                                # Facemoji keyboard (switched to Gboard first)
)

GBOARD=com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME

serial="${1:-}"
if [[ -z "$serial" ]]; then
  while read -r s state; do
    [[ "$state" == device ]] || continue
    if [[ "$(adb -s "$s" shell getprop ro.product.model | tr -d '\r')" == "$MODEL" ]]; then
      serial="$s"; break
    fi
  done < <(adb devices | tail -n +2)
fi
[[ -n "$serial" ]] || { echo "No $MODEL found in 'adb devices'." >&2; exit 1; }
echo "Using device $serial"

# Facemoji is her default keyboard; removing it first would leave none.
ime="$(adb -s "$serial" shell settings get secure default_input_method | tr -d '\r')"
if [[ "$ime" == com.preff.kb.xm/* ]]; then
  adb -s "$serial" shell ime enable "$GBOARD" >/dev/null
  adb -s "$serial" shell ime set "$GBOARD" >/dev/null
  ime="$(adb -s "$serial" shell settings get secure default_input_method | tr -d '\r')"
  if [[ "$ime" != "$GBOARD" ]]; then
    echo "Could not switch keyboard to Gboard (still $ime); not removing anything." >&2
    exit 1
  fi
  echo "keyboard switched to Gboard"
fi

# -e: enabled packages only, so an app this script already disabled is skipped.
installed="$(adb -s "$serial" shell pm list packages -e | tr -d '\r')"
system="$(adb -s "$serial" shell pm list packages -s | tr -d '\r')"
for pkg in "${REMOVE[@]}"; do
  if ! grep -qx "package:$pkg" <<<"$installed"; then
    echo "skip     $pkg (not installed)"; continue
  fi
  # A plain uninstall of a preinstalled app only strips its updates and
  # reports Success while the factory copy stays, so system apps skip it.
  if ! grep -qx "package:$pkg" <<<"$system"; then
    # adb exits non-zero when pm fails; "|| true" keeps set -e from aborting
    # before the fallbacks get a chance.
    out="$(adb -s "$serial" shell pm uninstall "$pkg" 2>&1 | tr -d '\r' || true)"
    if [[ "$out" == Success ]]; then
      echo "removed  $pkg"; continue
    fi
  fi
  out="$(adb -s "$serial" shell pm uninstall -k --user 0 "$pkg" 2>&1 | tr -d '\r' || true)"
  if [[ "$out" == Success ]]; then
    echo "removed  $pkg (preinstalled; user 0 only)"
    continue
  fi
  # HyperOS refuses to uninstall some of its own apps (Failure [-1000]),
  # but still lets them be disabled. Restore with: pm enable <package>
  out2="$(adb -s "$serial" shell pm disable-user --user 0 "$pkg" 2>&1 | tr -d '\r' || true)"
  if [[ "$out2" == *disabled-user* ]]; then
    echo "disabled $pkg (uninstall blocked: $out)"
  else
    echo "FAILED   $pkg: $out / $out2"
  fi
done
