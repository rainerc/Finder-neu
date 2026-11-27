#!/bin/zsh
# Diagnose: Warum verliert Twinfold nach einem Neubau die Berechtigung (Netzwerkvolumes, Festplattenvollzugriff)?
# Vergleicht die Signatur der installierten App mit dem, was macOS (TCC) zur erteilten Berechtigung gespeichert hat.
#
#   ./scripts/check-permissions.sh
#   VOLUME=/Volumes/Comics ./scripts/check-permissions.sh   → zusätzlich Mount-Infos des Volumes
#
# Für das Auslesen der TCC-Datenbanken braucht das Terminal selbst „Festplattenvollzugriff“
# (Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff → Terminal).
set -uo pipefail

APP="${1:-/Applications/Twinfold.app}"
BUNDLE_ID="com.example.FinderErsatz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== Signatur von $APP"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|CDHash)=' | head -6
CURRENT_DR="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
echo "Designated Requirement: $CURRENT_DR"
echo
echo "== Bundle-ID in der Info.plist: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)"
echo
echo "== Signierzertifikate im Schlüsselbund"
security find-identity -v -p codesigning | grep -E 'Apple Development|Developer ID Application' || echo "(keine)"
echo
echo "== Weitere Kopien der App, die Launch Services kennt"
mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true
echo

check_db() {
  local db="$1" label="$2"
  echo "== TCC ($label): $db"
  if ! sqlite3 "$db" "select 1" >/dev/null 2>&1; then
    echo "   nicht lesbar – dem Terminal „Festplattenvollzugriff“ geben und erneut starten"
    echo
    return
  fi
  local rows stored
  rows="$(sqlite3 -separator ' | ' "$db" "select service, auth_value, auth_reason, datetime(last_modified,'unixepoch','localtime') from access where client='$BUNDLE_ID'")"
  if [[ -z "$rows" ]]; then
    echo "   kein Eintrag für $BUNDLE_ID"
    echo
    return
  fi
  echo "   Dienst | auth_value (2 = erlaubt, 0 = verweigert) | Grund | geändert"
  echo "$rows" | sed 's/^/   /'
  for service in $(sqlite3 "$db" "select service from access where client='$BUNDLE_ID'"); do
    sqlite3 "$db" "select writefile('$TMP/$service.csreq', csreq) from access where client='$BUNDLE_ID' and service='$service'" >/dev/null 2>&1
    if [[ -s "$TMP/$service.csreq" ]]; then
      stored="$(csreq -r "$TMP/$service.csreq" -t 2>/dev/null)"
      if [[ "$stored" == "$CURRENT_DR" ]]; then
        echo "   $service: gespeicherte Signatur-Anforderung passt ✓"
      else
        echo "   $service: gespeicherte Signatur-Anforderung PASST NICHT ✗"
        echo "      gespeichert: $stored"
      fi
    else
      echo "   $service: keine Signatur-Anforderung gespeichert"
    fi
  done
  echo
}

check_db "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "Benutzer"
check_db "/Library/Application Support/com.apple.TCC/TCC.db" "System (Festplattenvollzugriff)"

echo "== Laufende Twinfold-Prozesse (welche Kopie läuft, seit wann?)"
ps -axo pid,lstart,command | grep -E '[F]inderErsatz' || echo "(keiner)"
echo

VOLUME="${VOLUME:-}"
if [[ -n "$VOLUME" ]]; then
  echo "== Volume $VOLUME"
  mount | grep -F " $VOLUME " || echo "(nicht eingehängt)"
  ls -ld@e "$VOLUME" 2>&1 | head -5
  echo
fi

echo "== Datenschutz-Entscheidungen von macOS für Twinfold (letzte 10 Minuten)"
log show --last 10m --style compact --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS[c] "FinderErsatz"' 2>/dev/null \
  | grep -iE 'auth|deny|denied|allow|service' | tail -25 || true
echo
echo "== Kernel/Sandbox-Meldungen zu Twinfold (letzte 10 Minuten)"
log show --last 10m --style compact --predicate '(process == "kernel" OR process == "sandboxd") AND eventMessage CONTAINS[c] "FinderErsatz"' 2>/dev/null \
  | tail -15 || true
