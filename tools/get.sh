#!/usr/bin/env bash
# One-line installer for people without a checkout: fetches tools/install.sh (and the TCL helper)
# and runs it with the APK from this repository.
#
#   curl -fsSL https://raw.githubusercontent.com/orange-tv888/orange-tv-update/main/tools/get.sh | TV=<tv-ip> bash
#   curl -fsSL .../get.sh | KEEP_ADB=1 TV=<tv-ip> bash      # TVs that switch ADB off (Xiaomi)
#   curl -fsSL .../get.sh | TV=<tv-ip> bash -s guard        # firmwares that refuse launchers
#   curl -fsSL .../get.sh | TV=<tv-ip> bash -s repair       # Home opens the TV's launcher again
#   curl -fsSL .../get.sh | TV=<tv-ip> bash -s restore      # give Home back to the TV's launcher
#   (Android 4.0-4.4 gets Orange Lite by itself; `bash -s lite` asks for it and is refused on 5.0+)
#
# Needs curl, unzip and python3 (TCL only). If adb is not installed, Google's platform-tools are
# downloaded into ~/.cache/orange and used from there.
#
# There is no Orange download site any more: the scripts come from this repository. When
# raw.githubusercontent.com is slow or blocked, try the two GitHub proxies below (the same set
# install.sh uses for the APK). jsDelivr was the old fallback but is unreachable in China
# (2026-11-11: HTTP 000 / SSL_ERROR_SYSCALL), so do not put it back.
# ORANGE_REF=<branch> reads another branch; AERIAL_REF is still read for older scripts.
set -euo pipefail
: "${TV:?set TV to the TV IP address, e.g. curl ... | TV=192.168.1.20 bash}"
REPO=orange-tv888/orange-tv-update
REF="${ORANGE_REF:-${AERIAL_REF:-main}}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
MIRRORS=(
  "$RAW"
  "https://ghfast.top/$RAW"
  "https://ghproxy.net/$RAW"
)

if ! command -v adb >/dev/null; then
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) echo "No adb found. Install Android platform-tools, then run again." >&2; exit 1 ;;
  esac
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/orange"
  if [ ! -x "$cache/platform-tools/adb" ]; then
    echo "adb not found; downloading Android platform-tools into $cache"
    mkdir -p "$cache"
    curl -fL --progress-bar -o "$cache/platform-tools.zip" "https://dl.google.com/android/repository/platform-tools-latest-$os.zip"
    unzip -q -o "$cache/platform-tools.zip" -d "$cache"
    rm -f "$cache/platform-tools.zip"
  fi
  export PATH="$cache/platform-tools:$PATH"
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/tools"
for f in install.sh restore.sh tcast-push.py; do
  ok=0
  for base in "${MIRRORS[@]}"; do
    if curl -fsSL --connect-timeout 8 "$base/tools/$f" -o "$dir/tools/$f" \
       && [ -s "$dir/tools/$f" ]; then ok=1; break; fi
  done
  [ "$ok" = 1 ] || { echo "Could not download tools/$f" >&2; exit 1; }
  # A proxy can return 200 with a truncated body; never run a half-downloaded script.
  case "$f" in
    *.sh) bash -n "$dir/tools/$f" || { echo "Incomplete script: tools/$f" >&2; exit 1; } ;;
  esac
done
chmod +x "$dir/tools/"*.sh "$dir/tools/tcast-push.py"

if [ "${1:-}" = restore ]; then
  shift
  "$dir/tools/restore.sh" "$@"
else
  "$dir/tools/install.sh" "$@"
fi
