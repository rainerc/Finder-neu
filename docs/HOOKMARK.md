# Hookmark mit Finder-Ersatz verwenden (⌃H)

Hookmark erkennt nur Apps, für die es ein Skript kennt. Finder-Ersatz stellt dafür per AppleScript
die Eigenschaften `selected paths` (ausgewählte Objekte im aktiven Fenster) und `current folder` bereit.

Voraussetzung: Hookmark Pro (eigene Skripte gibt es nur dort) und Finder-Ersatz als echte App
(`./scripts/build-app.sh`), nicht per `swift run`.

## Einrichten (einmalig)

1. Finder-Ersatz starten und in den Vordergrund holen.
2. Hookmark → Einstellungen → **Scripts** → „+“ bzw. die App „Finder-Ersatz“ wählen
   (Bundle-ID `com.example.FinderErsatz`).
3. Bei **Get Address** als Sprache **JavaScript** wählen und einfügen:

```javascript
const app = Application("Finder-Ersatz");
const paths = app.selectedPaths();
const path = paths.length > 0 ? paths[0] : app.currentFolder();
path ? $.NSURL.fileURLWithPath(path).absoluteString.js : "";
```

4. **Get Name** leer lassen (Hookmark nimmt bei Datei-Links den Dateinamen).
5. Beim ersten ⌃H fragt macOS, ob Hookmark Finder-Ersatz steuern darf → **Erlauben**.

Danach öffnet ⌃H auf einer markierten Datei oder einem Ordner das Hookmark-Fenster wie im Finder.
Ohne Auswahl wird der aktuelle Ordner verwendet.

Test im Terminal: `osascript -e 'tell application "Finder-Ersatz" to get selected paths'`
