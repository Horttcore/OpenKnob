#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This shell is $(uname -s), not a Mac."
  echo "Buzzer.app cannot open here. A bundle built on Linux is a Linux program and will not launch on your Mac either."
  echo
  echo "On your Mac, from this project:"
  echo "  ./scripts/package-app.sh && open Buzzer.app"
  echo
  echo "Scripted knob from this shell:"
  swift run -c release BuzzerMac --cli simulate
  exit 1
fi

swift build -c release --product BuzzerMac

APP="Buzzer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BuzzerMac "$APP/Contents/MacOS/BuzzerMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/BuzzerMac"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
echo "Open it with: open Buzzer.app"
