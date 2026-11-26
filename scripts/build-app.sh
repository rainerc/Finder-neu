#!/bin/zsh
# Baut Finder-Ersatz als echte, signierte .app (ohne Xcode-Projekt).
# Nötig, damit macOS die App als eigene App kennt und Berechtigungen
# (Netzwerkvolumes, lokales Netzwerk, Schreibtisch …) korrekt abfragt und speichert.
#
#   ./scripts/build-app.sh             → baut, installiert nach /Applications und startet
#   ./scripts/build-app.sh --no-install → nur build/Finder-Ersatz.app bauen und von dort starten
#   ./scripts/build-app.sh --no-open    → bauen und installieren, nicht starten
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Finder-Ersatz.app"
PLIST="$APP/Contents/Info.plist"

echo "▸ Kompiliere (Release) …"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/FinderErsatz"

echo "▸ Erzeuge $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FinderErsatz"
cp Support/Info.plist "$PLIST"
cp Support/FinderErsatz.sdef "$APP/Contents/Resources/"   # AppleScript-Schnittstelle (Hookmark)

pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null 2>&1 || true; }
pb "Add :CFBundleExecutable string FinderErsatz"
pb "Add :CFBundlePackageType string APPL"
pb "Add :CFBundleDisplayName string Finder-Ersatz"
pb "Add :CFBundleShortVersionString string 0.5"
pb "Add :CFBundleVersion string $(git rev-list --count HEAD 2>/dev/null || echo 1)"
pb "Add :LSMinimumSystemVersion string 26.0"
pb "Add :LSApplicationCategoryType string public.app-category.productivity"
pb "Add :NSHighResolutionCapable bool true"

# Mit dem eigenen Apple-Development-Zertifikat signieren (stabile Identität →
# macOS merkt sich erteilte Berechtigungen auch nach einem Neubau).
IDENTITY="$(security find-identity -v -p codesigning | grep -m1 -E 'Apple Development|Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
if [[ -n "$IDENTITY" ]]; then
  echo "▸ Signiere mit: $IDENTITY"
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "⚠︎ Kein Entwicklerzertifikat gefunden – ad-hoc-Signatur."
  echo "  (Xcode → Einstellungen → Accounts → Zertifikate verwalten → „Apple Development“ anlegen)"
  codesign --force --sign - "$APP"
fi

INSTALL=1; OPEN=1
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --no-open) OPEN=0 ;;
  esac
done

# Laufende App beenden, bevor sie ersetzt wird.
pkill -x FinderErsatz 2>/dev/null || true
sleep 0.5

TARGET="$APP"
if [[ $INSTALL == 1 ]]; then
  TARGET="/Applications/Finder-Ersatz.app"
  rm -rf "$TARGET"
  cp -R "$APP" "$TARGET"
  echo "✓ Installiert: $TARGET"
fi
echo "✓ Fertig"
if [[ $OPEN == 1 ]]; then
  open "$TARGET"
fi
exit 0
