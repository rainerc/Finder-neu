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

# AppleScript-Wörterbuch prüfen (für Hookmark)
if sdef "$APP" >/dev/null 2>&1; then
  echo "✓ AppleScript-Wörterbuch OK"
else
  echo "⚠︎ AppleScript-Wörterbuch fehlerhaft:"; sdef "$APP" 2>&1 | head -5 || true
fi

# Immer dasselbe Zertifikat (per SHA-1 fest gewählt) → gleiche „Designated Requirement“ →
# macOS behält erteilte Berechtigungen (Netzwerkvolumes, Festplattenvollzugriff) über Neubauten hinweg.
# Das einmal gewählte Zertifikat wird in .signing-identity gemerkt (nicht im Git), damit nie
# versehentlich ein anderes genommen wird (z. B. wenn ein zweites Zertifikat dazukommt).
IDENTITIES="$(security find-identity -v -p codesigning | grep -E 'Apple Development|Developer ID Application' || true)"
IDENTITY_HASH=""
if [[ -f .signing-identity ]]; then
  PINNED="$(head -1 .signing-identity | tr -d '[:space:]')"
  if echo "$IDENTITIES" | grep -q "$PINNED"; then
    IDENTITY_HASH="$PINNED"
  else
    echo "⚠︎ Gemerktes Zertifikat $PINNED nicht mehr gültig – wähle neu (Berechtigungen müssen dann einmal neu erteilt werden)."
  fi
fi
if [[ -z "$IDENTITY_HASH" ]]; then
  # Bevorzugt „Apple Development“, bei mehreren das erste nach Hash sortiert (stabil).
  IDENTITY_HASH="$( (echo "$IDENTITIES" | grep 'Apple Development'; echo "$IDENTITIES" | grep 'Developer ID Application') \
    | awk 'NF {print $2}' | head -1)"
  [[ -n "$IDENTITY_HASH" ]] && echo "$IDENTITY_HASH" > .signing-identity
fi
IDENTITY_NAME="$(echo "$IDENTITIES" | grep "$IDENTITY_HASH" | sed -E 's/.*"(.*)"/\1/' | head -1)"
if [[ -n "$IDENTITY_HASH" ]]; then
  echo "▸ Signiere mit: $IDENTITY_NAME ($IDENTITY_HASH)"
  codesign --force --options runtime --timestamp=none --identifier com.example.FinderErsatz --sign "$IDENTITY_HASH" "$APP"
else
  echo "⚠︎ Kein Entwicklerzertifikat gefunden – ad-hoc-Signatur. Berechtigungen gehen bei jedem Neubau verloren!"
  echo "  (Xcode → Einstellungen → Accounts → Zertifikate verwalten → „Apple Development“ anlegen)"
  codesign --force --sign - "$APP"
fi
DR="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
echo "▸ Designated Requirement: $DR"
# Warnen, wenn sich die Signatur-Anforderung gegenüber dem letzten Bau geändert hat –
# genau dann verwirft macOS erteilte Berechtigungen.
if [[ -f build/.last-dr && "$(cat build/.last-dr)" != "$DR" ]]; then
  echo "⚠︎ Designated Requirement hat sich geändert! Vorher: $(cat build/.last-dr)"
  echo "  macOS fragt Berechtigungen (Netzwerkvolumes, Festplattenvollzugriff) deshalb neu ab."
fi
echo "$DR" > build/.last-dr

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
  # Launch Services neu informieren (Name, AppleScript-Wörterbuch), Build-Kopie abmelden
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true
  echo "✓ Installiert: $TARGET"
fi
echo "✓ Fertig"
if [[ $OPEN == 1 ]]; then
  open "$TARGET"
fi
exit 0
