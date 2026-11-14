#!/bin/bash
# Compila Riquadri e lo installa in ~/Applications. Uso: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

LAVORO="${TMPDIR:-/tmp}/riquadri-build"
APP="$LAVORO/Riquadri.app"
rm -rf "$LAVORO"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Binario universale: Mac con chip Apple e Mac Intel.
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" Sources/*.swift -o "$LAVORO/Riquadri-$ARCH"
done
lipo -create "$LAVORO/Riquadri-arm64" "$LAVORO/Riquadri-x86_64" -output "$APP/Contents/MacOS/Riquadri"
cp Info.plist "$APP/Contents/Info.plist"

# Icona
swiftc -O tools/icona.swift -o "$LAVORO/icona"
"$LAVORO/icona" "$LAVORO/icona.png"
SET="$LAVORO/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$LAVORO/icona.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$LAVORO/icona.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force -s - "$APP"

# Archivio da condividere
ditto -c -k --keepParent "$APP" "$LAVORO/Riquadri.zip"

mkdir -p "$HOME/Applications"
pkill -x Riquadri 2>/dev/null || true
rm -rf "$HOME/Applications/Riquadri.app"
cp -R "$APP" "$HOME/Applications/Riquadri.app"
echo "Installata in $HOME/Applications/Riquadri.app"
