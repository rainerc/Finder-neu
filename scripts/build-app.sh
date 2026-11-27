#!/bin/zsh
# Baut Twinfold als echte, signierte .app (ohne Xcode-Projekt).
# Nötig, damit macOS die App als eigene App kennt und Berechtigungen
# (Netzwerkvolumes, lokales Netzwerk, Schreibtisch …) korrekt abfragt und speichert.
#
#   ./scripts/build-app.sh             → baut, installiert nach /Applications und startet
#   ./scripts/build-app.sh --no-install → nur build/Twinfold.app bauen und von dort starten
#   ./scripts/build-app.sh --no-open    → bauen und installieren, nicht starten
set -euo pipefail

cd "$(dirname "$0")/.."

# Schlägt der Bau fehl (z. B. Compilerfehler), bleibt die alte App installiert – deshalb deutlich melden,
# auch wenn die Ausgabe in eine Log-Datei umgeleitet wird (Kurzbefehl).
trap 'echo "✗ Bau fehlgeschlagen – die bisher installierte App wurde NICHT ersetzt."; \
  osascript -e "display alert \"Twinfold: Bau fehlgeschlagen\" message \"Die alte Version ist noch installiert. Fehler siehe Terminal bzw. Log.\" giving up after 60" >/dev/null 2>&1 || true' ERR
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unbekannt)"
echo "▸ Stand: Commit $COMMIT"
APP="build/Twinfold.app"
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
cp Support/AppIcon.icns "$APP/Contents/Resources/"        # App-Icon (Quelle: Support/Icon/AppIcon.svg)
cp -R Support/Localization/*.lproj "$APP/Contents/Resources/"   # Sprachen (de = Ausgangssprache, en)
for STRINGS in "$APP"/Contents/Resources/*.lproj/*.strings; do
  plutil -lint -s "$STRINGS" || { echo "✗ Übersetzungsdatei fehlerhaft: $STRINGS"; false; }
done

pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null 2>&1 || true; }
pb "Add :CFBundleExecutable string FinderErsatz"
pb "Add :CFBundlePackageType string APPL"
pb "Add :CFBundleDisplayName string Twinfold"
pb "Add :CFBundleIconFile string AppIcon"
pb "Add :CFBundleShortVersionString string 0.5"
pb "Add :CFBundleVersion string $(git rev-list --count HEAD 2>/dev/null || echo 1)"
pb "Add :FEGitCommit string $COMMIT"
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
  codesign --force --options runtime --timestamp=none --entitlements Support/Twinfold.entitlements --identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)" --sign "$IDENTITY_HASH" "$APP"
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
pkill -f '\.build/.*/FinderErsatz' 2>/dev/null || true   # auch Test-Builds (swift run / .build/debug)
sleep 0.5

TARGET="$APP"
if [[ $INSTALL == 1 ]]; then
  TARGET="/Applications/Twinfold.app"
  rm -rf "$TARGET"
  cp -R "$APP" "$TARGET"
  # Launch Services neu informieren (Name, AppleScript-Wörterbuch), Build-Kopie abmelden
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  # Alte Installation unter dem früheren Namen entfernen (gleiche Bundle-ID → Einstellungen und Berechtigungen bleiben)
  for OLD in "/Applications/Finder-Ersatz.app" "build/Finder-Ersatz.app"; do
    if [[ -d "$OLD" ]]; then
      "$LSREGISTER" -u "$OLD" >/dev/null 2>&1 || true
      rm -rf "$OLD"
      echo "▸ Alte App entfernt: $OLD"
    fi
  done
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true
  touch "$TARGET"   # Dock/Finder zeigen das neue Icon sofort
  # Spotlight sofort neu einlesen lassen – nach dem Löschen und Neukopieren fehlte die App sonst im Index
  mdimport "$TARGET" >/dev/null 2>&1 || true
  echo "✓ Installiert: $TARGET"
fi
echo "✓ Fertig (Commit $COMMIT)"
if [[ $OPEN == 1 ]]; then
  open "$TARGET"
fi
exit 0
