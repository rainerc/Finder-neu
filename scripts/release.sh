#!/bin/zsh
# Erstellt eine weitergebbare Twinfold-Version: mit „Developer ID Application“ signiert,
# von Apple notarisiert, Ticket angeheftet, als DMG.
#
#   ./scripts/release.sh 1.0          → build/release/Twinfold-1.0.dmg
#   ./scripts/release.sh 1.0 --no-notarize   → nur signieren (zum Testen)
#
# Einmalig vorher (siehe docs/RELEASE.md):
#   1. Zertifikat „Developer ID Application“ anlegen (Xcode → Einstellungen → Accounts → Zertifikate verwalten → +)
#   2. Zugangsdaten für die Notarisierung im Schlüsselbund speichern:
#      xcrun notarytool store-credentials twinfold --apple-id <Apple-ID> --team-id <TEAMID>
#      (fragt nach einem app-spezifischen Passwort von account.apple.com)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" || "$VERSION" == --* ]]; then
  echo "Aufruf: ./scripts/release.sh <Version> [--no-notarize]   z. B. ./scripts/release.sh 1.0"; exit 1
fi
NOTARIZE=1
[[ "${2:-}" == "--no-notarize" ]] && NOTARIZE=0
PROFILE="${NOTARY_PROFILE:-twinfold}"
ENTITLEMENTS="Support/Twinfold.entitlements"
OUT="build/release"
APP="$OUT/Twinfold.app"
DMG="$OUT/Twinfold-$VERSION.dmg"

trap 'echo "✗ Release fehlgeschlagen (siehe Meldungen oben)."' ERR

# 1. Developer-ID-Zertifikat suchen
IDENTITY="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | awk '{print $2}' | head -1 || true)"
if [[ -z "$IDENTITY" ]]; then
  echo "✗ Kein Zertifikat „Developer ID Application“ gefunden."
  echo "  Xcode → Einstellungen → Accounts → (Team wählen) → Zertifikate verwalten → + → Developer ID Application"
  exit 1
fi
echo "▸ Developer ID: $(security find-identity -v -p codesigning | grep "$IDENTITY" | sed -E 's/.*"(.*)"/\1/')"

if [[ $NOTARIZE == 1 ]] && ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "✗ Keine Notarisierungs-Zugangsdaten „$PROFILE“ im Schlüsselbund. Einmalig anlegen:"
  echo "  xcrun notarytool store-credentials $PROFILE --apple-id <Apple-ID> --team-id <TEAMID>"
  exit 1
fi

# 2. App bauen (ohne Installieren/Starten); build-app.sh beendet dabei eine laufende Twinfold-App
./scripts/build-app.sh --no-install --no-open
rm -rf "$OUT"; mkdir -p "$OUT"
ditto build/Twinfold.app "$APP"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"

# 3. Mit Developer ID signieren: Hardened Runtime + sicherer Zeitstempel (Pflicht für die Notarisierung)
echo "▸ Signiere $APP ($BUNDLE_ID) …"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
  --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

notarize() {   # $1 = Datei (zip oder dmg)
  echo "▸ Notarisiere $(basename "$1") (dauert meist 1–5 Minuten) …"
  local LOG="$OUT/notary-$(basename "$1").json"
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json > "$LOG" || true
  local STATUS="$(/usr/bin/plutil -extract status raw -o - "$LOG" 2>/dev/null || echo unbekannt)"
  if [[ "$STATUS" != "Accepted" ]]; then
    echo "✗ Notarisierung: $STATUS"
    local ID="$(/usr/bin/plutil -extract id raw -o - "$LOG" 2>/dev/null || true)"
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || cat "$LOG"
    exit 1
  fi
  echo "✓ Notarisierung angenommen"
}

# 4. App notarisieren und Ticket anheften (dann startet sie auch offline ohne Rückfrage bei Apple)
if [[ $NOTARIZE == 1 ]]; then
  ZIP="$OUT/Twinfold-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

# 5. DMG mit Verknüpfung zu „Programme“
echo "▸ Erzeuge $DMG …"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Twinfold.app"
ln -s /Applications "$STAGE/Programme"
hdiutil create -volname "Twinfold $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  # Gegenprobe: so prüft Gatekeeper auf fremden Macs
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "✓ Fertig: $DMG"
open -R "$DMG"
