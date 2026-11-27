# Twinfold weitergeben (Developer ID + Notarisierung)

Der Mac App Store kommt nicht infrage: er verlangt die App-Sandbox, und damit gingen
Festplattenvollzugriff, Befehlszeile, Terminal-Steuerung, SFTP/FTP über die Systemwerkzeuge,
Netzwerk-Einhängen und die Knopfleiste verloren. Stattdessen wird Twinfold wie Path Finder
als signierte, von Apple notarisierte DMG verteilt.

## Einmalig einrichten

1. **Apple Developer Program** (99 €/Jahr) unter developer.apple.com/programs – Team-ID steht danach unter
   developer.apple.com/account → Mitgliedschaft.
2. **Zertifikat „Developer ID Application“** anlegen: Xcode → Einstellungen → Accounts → Team wählen →
   „Zertifikate verwalten …“ → „+“ → „Developer ID Application“.
   Prüfen: `security find-identity -v -p codesigning` zeigt eine Zeile „Developer ID Application: …“.
3. **App-spezifisches Passwort** auf account.apple.com → Anmeldung und Sicherheit → App-spezifische Passwörter.
4. **Zugangsdaten für die Notarisierung** im Schlüsselbund speichern:
   ```
   xcrun notarytool store-credentials twinfold --apple-id <Apple-ID> --team-id <TEAMID>
   ```
   (fragt nach dem app-spezifischen Passwort; danach nie wieder)

## Version erstellen

```
cd ~/finder-neu && git pull && ./scripts/release.sh 1.0
```

Ergebnis: `build/release/Twinfold-1.0.dmg` (+ `.sha256`). Das Skript baut, signiert mit Hardened Runtime
und Zeitstempel, lässt App und DMG notarisieren, heftet die Tickets an und prüft mit `spctl` wie Gatekeeper.
Bei abgelehnter Notarisierung zeigt es Apples Protokoll.

Nur signieren, ohne Notarisierung (Test): `./scripts/release.sh 1.0 --no-notarize`

## Hinweise

- Die tägliche Arbeitsversion baut weiter `./scripts/build-app.sh` (Apple-Development-Zertifikat).
  Die Developer-ID-Version hat eine andere Signatur → macOS fragt Berechtigungen (Festplattenvollzugriff)
  für sie einmal neu ab.
- Entitlements: `Support/Twinfold.entitlements` (Apple Events für Terminal/Finder; ohne sie blockiert die
  Hardened Runtime diese Steuerung).
- Vor der ersten öffentlichen Version sollte die Bundle-ID von `com.example.FinderErsatz` auf eine eigene
  wechseln (z. B. `de.<domain>.twinfold`) – mit Übernahme der Einstellungen aus der alten Domain.
