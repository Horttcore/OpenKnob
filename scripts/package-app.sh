#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

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
