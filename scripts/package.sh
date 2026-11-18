#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/CofferCore/Protocol.swift")"
test -n "$VER"
STAGE="$(mktemp -d /tmp/ferret9-pkg.XXXXXX)"
BIN="$STAGE/bin"
bash "$ROOT/scripts/build.sh" "$BIN"
"$BIN/ferret9-tests"

APP="$STAGE/Ferret9.app"
mkdir -p "$APP/Contents/MacOS" "$STAGE/payload/usr/local/bin" "$STAGE/payload/Library/PrivilegedHelperTools" "$STAGE/payload/Library/LaunchDaemons" "$STAGE/scripts"
cp "$BIN/Ferret9" "$APP/Contents/MacOS/Ferret9"
chmod 755 "$APP/Contents/MacOS/Ferret9"

ICON_SRC="$ROOT/docs/app-icon.png"
ICON_BUNDLE="$ROOT/packaging/AppIcon.icns"
if [[ -f "$ICON_BUNDLE" ]]; then
  mkdir -p "$APP/Contents/Resources"
  cp "$ICON_BUNDLE" "$APP/Contents/Resources/AppIcon.icns"
  ICON_PLIST=$'\n<key>CFBundleIconFile</key><string>AppIcon</string>'
elif [[ -f "$ICON_SRC" ]]; then
  mkdir -p "$APP/Contents/Resources"
  ICONSET="$STAGE/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  declare -a SIZES=(16 32 128 256 512)
  for size in "${SIZES[@]}"; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    dbl=$((size * 2))
    if [[ "$size" -eq 512 ]]; then dbl=1024; fi
    sips -z "$dbl" "$dbl" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    ICON_PLIST=$'\n<key>CFBundleIconFile</key><string>AppIcon</string>'
  else
    ICON_PLIST=""
  fi
  rm -rf "$ICONSET"
else
  ICON_PLIST=""
fi
cp "$BIN/ferret9-cli" "$STAGE/payload/usr/local/bin/ferret9"
cp "$BIN/ferret9-service" "$STAGE/payload/Library/PrivilegedHelperTools/ferret9-service"
cp "$ROOT/packaging/com.ferret9.service.plist" "$STAGE/payload/Library/LaunchDaemons/com.ferret9.service.plist"
cp "$ROOT/packaging/scripts/preinstall" "$ROOT/packaging/scripts/postinstall" "$STAGE/scripts/"
chmod 755 "$STAGE/scripts/preinstall" "$STAGE/scripts/postinstall"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ferret9</string>
<key>CFBundleIdentifier</key><string>com.ferret9.app</string>
<key>CFBundleName</key><string>Ferret9</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>LSUIElement</key><false/>
<key>LSBackgroundOnly</key><false/>
<key>NSPrincipalClass</key><string>NSApplication</string>${ICON_PLIST}
</dict></plist>
EOF

OUT="${1:-/tmp/Ferret9-$VER.pkg}"
pkgbuild --root "$STAGE/payload" --scripts "$STAGE/scripts" --identifier com.ferret9.pkg --version "$VER" --install-location / "$STAGE/root.pkg" >/dev/null
# App is not in the daemon payload; ship it beside the pkg so Spotlight does not index a repo copy.
APP_DEST="$(dirname "$OUT")/Ferret9.app"
rm -rf "$APP_DEST"
cp -R "$APP" "$APP_DEST"
mv "$STAGE/root.pkg" "$OUT"
rm -rf "$STAGE"
echo "$OUT"
echo "$(dirname "$OUT")/Ferret9.app"
