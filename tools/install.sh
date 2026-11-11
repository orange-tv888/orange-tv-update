#!/usr/bin/env bash
# Install Orange on a TV over ADB and make it the home screen.
#
#   TV=<tv-ip> tools/install.sh               # standard build (declares HOME)
#   TV=<tv-ip> tools/install.sh guard         # for firmwares that refuse to install a launcher
#   TV=<tv-ip> tools/install.sh               # network ADB kept on by default (26.5.5)
#   KEEP_ADB=0 TV=<tv-ip> tools/install.sh     # explicitly leave ADB alone
#   TV=<tv-ip> tools/install.sh repair        # Home went back to the TV's launcher: restart Home Guard
#   TV=<tv-ip> tools/install.sh lite          # Orange Lite; chosen by itself on Android 4.0-4.4,
#                                             # refused on 5.0+ (FORCE_LITE=1 to try it there)
#
# The APK comes from this repository (update/orange.apk on main, else jsDelivr's copy), so only adb
# is needed (and python3 on TCL TVs).
#   BUILD=1        build it from this checkout instead (JDK 17 + Android SDK)
#   APK_FILE=<apk> install this file instead
#   STAY_CONNECTED=1  stay connected to the TV afterwards (otherwise adb lets go of it at the end)
#
# Takeover, gentlest first. Nothing is uninstalled or disabled:
#   1. Ask Android: HOME role / preferred home activity. Works on stock Android TV and Google TV.
#   2. If the firmware pins Home to its own launcher anyway (Xiaomi PatchWall, TCL, most China-market
#      firmware), Orange Home Guard takes over: an accessibility service that answers the Home key
#      and steps in front of the stock launcher. Firmwares that force-stop third-party apps on standby
#      (Xiaomi) switch accessibility services off; a notification-listener binding brings Orange back
#      (or, where Android refuses listeners, a sync adapter about 30 s later: guard/RevivalSync.kt)
#      and Orange switches the guard on again, which is what WRITE_SECURE_SETTINGS is granted for.
#
# Firmwares that block every ADB install (TCL's package verifier) get it through TCL's own 多屏互动,
# with one confirmation on the TV; failing that, the APK is pushed to Download and installed through
# an app store's local install (Dangbei).
#
# tools/restore.sh undoes all of it.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TV:?set TV to the TV IP address, e.g. TV=<tv-ip> $0}"
# 26.5.6 拆仓：源码仓 orange--tv 已转 Private，APK 只从公开的更新仓下载。
# 这里只用于拉 update/orange.apk；别改回源码仓，否则匿名下载 404。
REPO=orange-tv888/orange-tv-update
command -v adb >/dev/null || { echo "adb not found. macOS: brew install android-platform-tools; Linux: install android-tools / adb." >&2; exit 1; }
FLAVOR="${1:-standard}"
case "$FLAVOR" in standard|guard|repair|lite) ;; *) echo "flavor must be standard, guard or lite (or repair)" >&2; exit 1 ;; esac
PKG=app.orange.tv
GUARD="$PKG/$PKG.guard.HomeGuardService"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [ "${BUILD:-0}" = 1 ]; then
  export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null || echo /opt/homebrew/opt/openjdk@17)}"
  [ -f local.properties ] || echo "sdk.dir=$ANDROID_HOME" > local.properties
fi

case "$TV" in *:*) SERIAL="$TV" ;; *) SERIAL="$TV:5555" ;; esac
export ANDROID_SERIAL="$SERIAL"
# Let go of the TV at the end unless it was connected before: some TVs take one computer at a time,
# and the phone apps the owner uses next (甲壳虫 and the like) could not connect until this
# computer's adb server dropped it (issue #764). STAY_CONNECTED=1 keeps it.
if [ "${STAY_CONNECTED:-0}" != 1 ] && ! adb devices 2>/dev/null | grep -q "^$SERIAL[[:space:]]"; then
  trap 'adb disconnect "$SERIAL" >/dev/null 2>&1 || true; [ -n "${MAIN_SERIAL:-}" ] && adb disconnect "$MAIN_SERIAL" >/dev/null 2>&1; true' EXIT
fi
adb connect "$SERIAL" >/dev/null
STATE=$(adb get-state 2>&1 || true)
if [ "$STATE" != device ]; then
  case "$STATE" in
    *unauthorized*) echo "The TV is asking \"Allow USB debugging?\". Choose Allow (and Always allow) on the TV, then run again." ; exit 1 ;;
  esac
  # Android 11+ "Wireless debugging" never answers on 5555: adbd speaks TLS on ports that change
  # every visit, and the first connection needs a 6-digit pairing code (TCL Q9M / Q10L and other
  # 2026 firmwares only expose this mode, issue #31). Pair once, then put adbd back on 5555 so
  # the runs after this one (and KEEP_ADB) work the usual way. Some TCL firmwares (Q10M, 鹤 7 Pro)
  # have no pairing-code entry at all; the only way in there is a USB cable, then adb tcpip 5555.
  # Android 11+ TVs with only wireless debugging use a TLS port of their own and refuse an
  # unpaired computer's certificate (TCL 85T7L Ultra, issue #480).
  PAIRED=0
  if [ -n "${ADB_PAIR:-}" ] && [ -n "${ADB_CODE:-}" ] && [ -n "${ADB_CONNECT:-}" ]; then
    adb pair "$ADB_PAIR" "$ADB_CODE" || echo "Pairing failed: check the code, it expires quickly." >&2
    if adb connect "$ADB_CONNECT" >/dev/null && [ "$(adb get-state 2>/dev/null)" = device ]; then
      PAIRED=1; MAIN_SERIAL="$ADB_CONNECT"
    fi
  elif [ -t 0 ]; then
    echo "The TV did not accept $SERIAL. On Android 11+ it may be on wireless debugging, which pairs first:"
    echo "on the TV open Developer options → Wireless debugging → Pair device with pairing code."
    printf "IP:port shown on the pairing screen (blank to skip): "; read -r PAIR
    if [ -n "$PAIR" ]; then
      printf "6-digit pairing code: "; read -r CODE
      adb pair "$PAIR" "$CODE" || echo "Pairing failed: check the code, it expires quickly." >&2
      echo "The main wireless-debugging screen shows another IP:port (it changes every time)."
      printf "IP:port to connect to: "; read -r MAIN
      if [ -n "$MAIN" ] && adb connect "$MAIN" >/dev/null && [ "$(adb get-state 2>/dev/null)" = device ]; then
        PAIRED=1; MAIN_SERIAL="$MAIN"
      else
        echo "Connecting to $MAIN did not work; read the IP:port on the wireless-debugging screen again." >&2
      fi
    fi
  else
    echo "Could not connect to $SERIAL. Check that ADB debugging is on and the IP is right. A TV that offers only wireless debugging (Android 11+) needs pairing first: adb pair <IP>:<pairing port> with the code the TV shows, then run again with TV=<IP>:<port the TV shows>." >&2
    echo "Or rerun with ADB_PAIR=<pair-screen ip:port> ADB_CODE=<6-digit code> ADB_CONNECT=<main-screen ip:port> set." >&2
  fi
  if [ "$PAIRED" = 1 ]; then
    # Plaintext 5555 keeps working without pairing again; the pairing only authorizes this key.
    if adb tcpip 5555 >/dev/null 2>&1; then sleep 2; adb connect "$SERIAL" >/dev/null; fi
    if [ "$(adb get-state 2>/dev/null)" = device ]; then
      echo "Paired; adbd is back on 5555. The usual IP works for later runs."
    else
      export ANDROID_SERIAL="$MAIN_SERIAL"; echo "Staying on $MAIN_SERIAL for this run; the next run pairs again." >&2
    fi
  else
    # Pairing was tried and did not get through; without a terminal the hint above says it all.
    if [ -n "${ADB_PAIR:-}" ] || [ -t 0 ]; then
      echo "Still not connected. Read the IP:port and code on the TV's wireless-debugging screen again, then run again." >&2
    fi
    exit 1
  fi
fi

# What counts is the service Android actually runs, not the settings entry: after an update, Xiaomi
# MiTV-MFTP0 (Android 9) kept the entry while system_server still pointed at the old APK directory
# and never bound it (issue #72).
# Some firmwares show the class name where the label goes (Xiaomi MiTV-ASTP0, Android 9, issue #183).
guard_bound() { adb shell dumpsys accessibility 2>/dev/null | grep -q -E "label=(Orange|app\.orange\.tv)"; }

wait_guard() {
  for _ in $(seq 1 "$1"); do sleep 1; guard_bound && return 0; done
  return 1
}

# Stopping Orange makes system_server load it afresh, from the APK that is really installed; the
# guard is bound again when it starts (verified on MiTV-MFTP0, issue #72).
restart_orange() {
  adb shell am force-stop "$PKG"
  sleep 3
  adb shell am start -W -n "$PKG/.MainActivity" >/dev/null 2>&1 || true
}

# Grants that only ADB can give; Orange never asks for them on screen. Again on repair: an APK
# installed without this script has none of them, and Home Guard never came on (issue #853).
grant() {
  adb shell pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS 2>/dev/null || true  # keep Home Guard (and ADB) on
  adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow 2>/dev/null || true             # open Orange after boot
  adb shell appops set "$PKG" WRITE_SETTINGS allow 2>/dev/null || true                  # brightness
  adb shell appops set "$PKG" REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true        # update from Control Center
  # What is in front, where a launcher hides from accessibility (Xiaomi Android 6, issue #81).
  # Android 5 knows the op only by this name.
  adb shell appops set "$PKG" GET_USAGE_STATS allow 2>/dev/null || true
  adb shell appops set "$PKG" android:get_usage_stats allow 2>/dev/null || true
  # Android 13 and later restrict an app installed from a file (a USB stick, a file manager, Orange's
  # own update before 1.63): its accessibility service may not be switched on. Both TVs where Home
  # Guard kept going off had it denied (OBE R3 Ultra Max and TCL 75T7M Pro, Android 14, issues #811
  # #829). Older Android does not know the op, which is fine.
  adb shell appops set "$PKG" ACCESS_RESTRICTED_SETTINGS allow 2>/dev/null || true
  # TCL's 自启动管理 (TclAppBootManager in system_server) refuses to start or bind third-party apps
  # after a reboot unless these TCL-only app ops allow it; without them the TV boots to TCL's launcher.
  # FFALCON T966D5 (Android 14) names them AUTO_START / ASSOC_START (issue #817); it also puts them
  # back to ignore on every boot, so there they last until the next reboot only.
  # Other firmwares do not know the op names and refuse them, which is fine.
  for op in APP_AUTO_START APP_ASSOC_START AUTO_START ASSOC_START; do
    adb shell appops set "$PKG" "$op" allow >/dev/null 2>&1 || true
  done
  adb shell cmd notification allow_listener "$PKG/$PKG.guard.RevivalListener" 2>/dev/null || true  # come back after a kill
}

# Android 4.0-4.4 cannot run the full app (Jetpack Compose needs Android 5.0). Orange Lite is a
# separate package that declares HOME and has no Home Guard, so the owner picks it once in
# Android's home chooser (docs/LITE.md). Nothing else from the steps below applies.
# Each build is refused on the other side of 5.0: Android rejects the full app below 5.0 by itself,
# but nothing stops Lite (minSdk 14) on a newer TV, where it would add a second HOME candidate next
# to Orange and the stock launcher. FORCE_LITE=1 is for trying Lite on a new TV (docs/LITE.md).
SDK=$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
OLD_ANDROID=0
[ -n "$SDK" ] && [ "$SDK" -lt 21 ] 2>/dev/null && OLD_ANDROID=1
if [ "$FLAVOR" = lite ] && [ "$OLD_ANDROID" = 0 ] && [ "${FORCE_LITE:-0}" != 1 ]; then
  echo "This TV runs Android $(adb shell getprop ro.build.version.release | tr -d '\r'): Orange Lite is only for Android 4.0-4.4. Run the command without \"lite\" to install Orange." >&2
  exit 1
fi
if [ "$OLD_ANDROID" = 1 ] && [ -n "${1:-}" ] && [ "$FLAVOR" != lite ]; then
  echo "This TV runs Android $(adb shell getprop ro.build.version.release | tr -d '\r'), and Orange needs 5.0 or newer. Run the command without \"$FLAVOR\" to install Orange Lite, the version for Android 4.0-4.4." >&2
  exit 1
fi
if [ "$FLAVOR" = lite ] || [ "$OLD_ANDROID" = 1 ]; then
  LITE=app.orange.tv.lite
  [ "$FLAVOR" = lite ] || echo "This TV runs Android $(adb shell getprop ro.build.version.release | tr -d '\r'): installing Orange Lite, the version for Android 4.0-4.4 (first release, a beta)."
  if [ -n "${APK_FILE:-}" ]; then APK=$APK_FILE
  else
    # Lite is not published (docs/release/CHECKLIST.md B6): there is no download to fall back on,
    # so build it from this checkout.
    echo "Orange Lite is not published; building it from this checkout." >&2
    ./gradlew -q --console=plain :lite:assembleRelease
    APK=lite/build/outputs/apk/release/lite-release.apk
  fi
  echo "Installing $APK"
  OUT=$(adb install -r "$APK" 2>&1 | tr -d '\r') || true
  echo "$OUT" | tail -n 2
  echo "$OUT" | grep -q Success || { echo "Installing failed. Copy the APK to a USB drive and open it with the TV's file manager, or see https://github.com/$REPO" >&2; exit 1; }
  # Brightness on TVs that keep it in a secure or global setting (Xiaomi picture_backlight).
  # Android 4.0 cannot grant it from the shell; the slider then opens the TV's picture settings.
  adb shell pm grant "$LITE" android.permission.WRITE_SECURE_SETTINGS >/dev/null 2>&1 || true
  adb shell am start -n "$LITE/.HomeActivity" >/dev/null 2>&1 || true
  echo
  echo "Orange Lite is installed and open. Press Home on the remote; when Android asks which app to use,"
  echo "choose Orange Lite, then Always. If no question comes and the old launcher opens, the firmware"
  echo "keeps Home for its own launcher: open Orange Lite from the app list instead."
  exit 0
fi

if [ "$FLAVOR" = repair ]; then
  adb shell pm path "$PKG" >/dev/null 2>&1 || { echo "Orange is not installed on this TV." >&2; exit 1; }
  grant
  restart_orange
  if wait_guard 8; then echo "Home Guard is running again. Press Home on the remote."; exit 0; fi
  echo "Orange is open, but Home Guard is not running. Run the install command again." >&2
  exit 1
fi

# Path of the APK for a flavor: APK_FILE, a local build, or the latest release.
build() {
  local flavor=$1
  if [ -n "${APK_FILE:-}" ] && [ "$flavor" = "$FLAVOR" ]; then
    echo "$APK_FILE"
  elif [ "${BUILD:-0}" = 1 ]; then
    local task="assemble$(tr '[:lower:]' '[:upper:]' <<< "${flavor:0:1}")${flavor:1}Release"
    ./gradlew -q --console=plain "$task"
    echo "app/build/outputs/apk/$flavor/release/app-$flavor-release.apk"
  else
    local out="${TMPDIR:-/tmp}/orange-$flavor.apk" url
    # Orange publishes one APK, update/orange.apk (the standard build). There is no Release page
    # and no guard build to download, so those two say so instead of pulling a stranger's launcher.
    if [ "$flavor" != standard ]; then
      echo "No published $flavor build. Run again with BUILD=1 to build it from this checkout, or APK_FILE=<apk>." >&2
      return 1
    fi
    for url in "https://raw.githubusercontent.com/$REPO/main/update/orange.apk" \
               "https://cdn.jsdelivr.net/gh/$REPO@main/update/orange.apk"; do
      echo "Downloading $url" >&2
      if curl -fL --progress-bar --connect-timeout 10 -o "$out" "$url"; then echo "$out"; return; fi
    done
    echo "Could not download orange.apk" >&2
    return 1
  fi
}

version_code() {   # versionCode of the APK on disk; empty without the Android SDK
  # Several build-tools versions may be installed; a bare glob would pass the others as arguments.
  local aapt2
  aapt2=$(ls "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
  [ -n "$aapt2" ] || return 0
  "$aapt2" dump badging "$1" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1
}

installed_code() {
  adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1
}

# Installed by now: the expected versionCode when known, else any change from before.
installed_now() {
  local now
  now=$(installed_code)
  if [ -n "$WANT" ]; then [ "$now" = "$WANT" ]; else [ -n "$now" ] && [ "$now" != "$BEFORE" ]; fi
}

# TCL's 多屏互动 (system app) installs APKs that TCL's phone app pushes to it; tools/tcast-push.py
# speaks that protocol. The TV downloads the APK from this computer through an ADB reverse tunnel,
# so nothing is served on the network. The viewer confirms once on the TV (同意).
tcast_install() {
  local apk=$1 want=$2 dir srv rc=0
  nc -z -G 3 "${SERIAL%%:*}" 6553 >/dev/null 2>&1 || return 1
  dir=$(mktemp -d)
  cp "$apk" "$dir/Orange.apk"
  python3 -m http.server 8765 --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
  srv=$!
  adb reverse tcp:8765 tcp:8765 >/dev/null
  echo "Pushing Orange through 多屏互动. On the TV, choose 同意 (Agree)."
  python3 tools/tcast-push.py "${SERIAL%%:*}" http://127.0.0.1:8765/Orange.apk "$PKG" Orange "${want:-0}" 180 || rc=$?
  adb reverse --remove tcp:8765 >/dev/null 2>&1 || true
  { kill "$srv" && wait "$srv"; } 2>/dev/null || true
  rm -rf "$dir"
  return $rc
}

BEFORE=$(installed_code)
APK=$(build "$FLAVOR")
echo "Installing $APK"
# Some firmwares exit 0 on a failed install (TCL p331, Android 5.1: "Failure [INSTALL_PARSE_FAILED_
# INCONSISTENT_CERTIFICATES]" with exit 0, issue #1017), so only "Success" counts.
OUT=$(adb install -r "$APK" 2>&1); RC=$?
if [ "$RC" -ne 0 ] || ! printf '%s\n' "$OUT" | grep -q Success; then
  echo "$OUT" >&2
  case "$OUT" in
    *VERIFICATION_FAILURE*)
      # TCL: ADB installs are refused outright, and so is any APK that declares a home screen and is
      # not signed by TCL. The guard build declares none.
      [ "$FLAVOR" = guard ] || APK=$(build guard)
      WANT=$(version_code "$APK")
      echo
      TCAST_OK=0
      if tcast_install "$APK" "$WANT"; then
        TCAST_OK=1
      else
        # No 多屏互动: put the APK in Download and install it on the TV itself.
        adb shell rm -f /sdcard/Download/Orange.apk
        adb push "$APK" /sdcard/Download/Orange.apk >/dev/null
        adb shell content call --uri content://media --method scan_volume --arg external_primary >/dev/null 2>&1 || true
        echo "This TV only installs apps from the TV itself. Orange.apk is now in Download on the TV."
        if adb shell pm path com.dangbeimarket >/dev/null 2>&1; then
          adb shell am start -n com.dangbeimarket/.ui.apkmanager.ApkManagerActivity >/dev/null 2>&1 || true
          echo "Dangbei's package manager is open on the TV: choose Orange, then Install (confirm on the TV)."
        else
          echo "Open it with a file manager or an app store's local install already on the TV, and confirm."
          echo "Do not install another app (an app store or a tool) to do this: Orange is the only app this installs."
        fi
        echo -n "Waiting for the install"
        for _ in $(seq 1 120); do
          installed_now && break
          echo -n "."; sleep 3
        done
        echo
      fi
      [ "$TCAST_OK" = 1 ] || installed_now || { echo "Orange was not installed; nothing else was changed." >&2; exit 1; }
      FLAVOR=guard
      ;;
    *INCONSISTENT_CERTIFICATES*|*UPDATE_INCOMPATIBLE*)
      echo "The Orange on this TV is signed with another key (a build of someone else's), so it cannot be updated in place." >&2
      echo "Uninstall it first (this drops its settings, wallpapers and photos): adb uninstall $PKG" >&2
      exit 1
      ;;
    *)
      [ "$FLAVOR" = standard ] && echo "This firmware may refuse apps that declare a home screen. Try: TV=$TV $0 guard" >&2
      exit 1
      ;;
  esac
fi

grant
# Android 9 on Xiaomi MiTV-MFTP0 reports success but never binds it (issue #72): low-RAM devices
# get no notification listeners at all. Orange's sync adapter brings it back there instead, later.
if ! adb shell dumpsys notification 2>/dev/null | grep -q "$PKG/$PKG.guard.RevivalListener"; then
  echo "Note: this TV refuses notification listeners. After the TV stops Orange (Xiaomi does at standby)," >&2
  echo "Orange comes back through Android's sync service about 30-60 seconds later, not at once: after a" >&2
  echo "short standby the TV's launcher can show for up to a minute. Keep auto-sync on. If Home ever stays" >&2
  echo "on the TV's launcher: TV=$TV $0 repair" >&2
fi
# TVs on Android's standard screensaver (TCL's carries a membership upsell) get Orange's instead,
# so it also starts while another app sits idle. Xiaomi uses its own; Orange covers it from Home.
if [ "$(adb shell settings get secure screensaver_enabled | tr -d '\r')" = 1 ]; then
  adb shell settings put secure screensaver_components "$PKG/$PKG.dream.OrangeDream"
  # Some firmwares (TCL) put their own back on every boot; Orange restores it when it starts.
  adb shell am broadcast -a "$PKG.CONFIG" -n "$PKG/.guard.ConfigReceiver" --ez own_screensaver true >/dev/null
  echo "Orange's screensaver is now the TV's screensaver."
fi
# 26.5.5: keeping network ADB on is the DEFAULT (user 15:17 hard constraint). The old
# KEEP_ADB=1 opt-in was never sent by releases that used `adb install -r`, so the mechanism
# sat idle and a wake could leave 5555 closed. KEEP_ADB=0 is now the explicit opt-out.
if [ "${KEEP_ADB:-1}" = 0 ]; then
  adb shell am broadcast -a "$PKG.CONFIG" -n "$PKG/.guard.ConfigReceiver" --ez keep_adb false >/dev/null
  echo "ADB keep-alive explicitly OFF (KEEP_ADB=0)."
else
  adb shell am broadcast -a "$PKG.CONFIG" -n "$PKG/.guard.ConfigReceiver" \
    --ez keep_adb true --ez adb_tcp_known true >/dev/null
  echo "ADB keep-alive ON by default: Orange restores adb_enabled and 5555 after a wake/reboot."
fi

if ! adb shell am start -W -n "$PKG/.MainActivity" | grep -q "Status: ok"; then
  echo "Orange did not start; Home was left untouched." >&2
  exit 1
fi

# 26.5.5 three-state self-check: keep_adb / adb_enabled / 5555. Printed on every install so
# "ADB stays on" is verifiable rather than something the operator has to remember (QA 16).
ADB_STATE=$(adb shell am broadcast -a "$PKG.CONFIG" -n "$PKG/.guard.ConfigReceiver" 2>/dev/null \
  | tr -d '\r' | awk -F'data="' 'NF>1 {print $2}' | tr -d '"')
ADB_IP="${SERIAL%:*}"
if nc -z -G 2 "$ADB_IP" 5555 2>/dev/null || nc -z -w 2 "$ADB_IP" 5555 2>/dev/null; then
  ADB_PORT=open
else
  ADB_PORT=closed
fi
echo "ADB three-state self-check: ${ADB_STATE:-<no reply from Orange yet>}"
echo "ADB three-state self-check: 5555=$ADB_PORT (probed from this computer; SELinux stops the app from probing it)"

# Compose runs much smoother ahead-of-time compiled on TV chips: Home's tiles show in about half the
# time. After Orange's first start, not before: some firmwares compile "speed" as "speed-profile"
# (Xiaomi MiTV-MFTR0, Android 14), which needs the profile Orange writes as it starts; compiled
# straight after the install it was left interpreted ("verify").
sleep 5
adb shell cmd package compile -m speed -f "$PKG" >/dev/null 2>&1 || true

# With CATEGORY_DEFAULT, as Home itself is resolved: on XGIMI m7642 (Android 9) a query without it
# lists Settings' FallbackHome too, and Android drops the default Home over the changed set (#767).
resolve_home() {
  adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME -c android.intent.category.DEFAULT \
    | tail -n 1 | tr -d '\r'
}

if [ "$FLAVOR" = standard ]; then
  # Hisense VIDAA (MT9653, Android 11, #40) starts the launcher named in this property by explicit
  # component, past the HOME role and unseen by Home Guard. Only firmwares that have it; the old
  # value is kept on the TV for restore.sh.
  VT_HOME=$(adb shell getprop persist.vt.use_home_pkg | tr -d '\r')
  if [ -n "$VT_HOME" ] && [ "$VT_HOME" != "$PKG" ]; then
    # Renamed from aerial_vt_home_pkg in 26.5.0. restore.sh reads either name, so a TV that stored
    # it under the old one still gets its launcher back; this runs on every install, so the value
    # ends up under the new name from now on.
    adb shell settings put global orange_vt_home_pkg "$VT_HOME"
    adb shell settings delete global aerial_vt_home_pkg >/dev/null 2>&1 || true
    adb shell setprop persist.vt.use_home_pkg "$PKG"
    echo "Hisense: Home now opens Orange instead of $VT_HOME."
  fi
  # Not on Xiaomi (PatchWall, com.mitv.tvhome installed): most firmwares ignore it, but one Android 9
  # set took it, PatchWall then ran as an ordinary app outside the home stack, and Xiaomi's short
  # press of the power key crashed its settings app and never put the TV to sleep (#848). Home
  # Guard takes over there as everywhere else on Xiaomi.
  if [ -z "$(adb shell pm path com.mitv.tvhome 2>/dev/null | tr -d '\r')" ]; then
    adb shell cmd role add-role-holder --user 0 android.app.role.HOME "$PKG" >/dev/null 2>&1 \
      || adb shell cmd package set-home-activity --user 0 "$PKG/.MainActivity" >/dev/null 2>&1 || true
  fi
  HOME_NOW=$(resolve_home)
  case "$HOME_NOW" in
    "$PKG"/*)
      echo "Orange is the home screen ($HOME_NOW)."
      exit 0 ;;
  esac
  echo "The firmware still sends Home to $HOME_NOW; turning on Orange Home Guard."
fi

# Orange switches the guard on itself when it starts (it has WRITE_SECURE_SETTINGS by now). Do it
# here as well, appending to the list so no other service is dropped.
CURRENT=$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')
case "$CURRENT" in
  *"$GUARD"*) ;;
  null|"") adb shell settings put secure enabled_accessibility_services "$GUARD" ;;
  *) adb shell settings put secure enabled_accessibility_services "'$CURRENT:$GUARD'" ;;
esac
adb shell settings put secure accessibility_enabled 1

if wait_guard 6; then
  echo "Home Guard is running. Press Home on the remote."
  exit 0
fi
echo "Home Guard is enabled but Android has not started it; restarting Orange."
restart_orange
if wait_guard 8; then
  echo "Home Guard is running. Press Home on the remote."
  exit 0
fi
echo "Home Guard is enabled but Android has not started it." >&2
echo "Some TCL / Hisense firmwares block sideloaded accessibility services: allow Orange under the" >&2
echo "TV's security app (自启动 / 无障碍 / 权限管理), then run this script again." >&2
exit 1
