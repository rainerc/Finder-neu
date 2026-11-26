# Hookmark mit Finder-Ersatz verwenden (⌃H)

**Erst ohne Skript probieren:** Finder-Ersatz meldet das ausgewählte Objekt (bzw. den Ordner) als „Dokument“
des Fensters. Hookmark erkennt das bei vielen Apps automatisch. Klappt ⌃H damit nicht, das Skript unten einrichten.

Hookmark erkennt sonst nur Apps, für die es ein Skript kennt. Finder-Ersatz stellt dafür per AppleScript
die Eigenschaften `selected paths` (ausgewählte Objekte im aktiven Fenster) und `current folder` bereit.

Voraussetzung: Hookmark Pro (eigene Skripte gibt es nur dort) und Finder-Ersatz als echte App
(`./scripts/build-app.sh`), nicht per `swift run`.

## Einrichten (einmalig)

1. Finder-Ersatz starten und in den Vordergrund holen.
2. Hookmark → Einstellungen → **Scripts** → „+“ bzw. die App „Finder-Ersatz“ wählen
   (Bundle-ID `com.example.FinderErsatz`).
3. Bei **Get Address** dieses AppleScript einfügen (getestet, funktioniert; JavaScript nimmt Hookmark hier nicht an):

```applescript
use framework "Foundation"
use scripting additions
tell application "/Applications/Finder-Ersatz.app" to set thePaths to selected paths
if thePaths is {} then return ""
return ((current application's NSURL's fileURLWithPath:(item 1 of thePaths))'s absoluteString()) as text
```

   Wichtig: die App über ihren Pfad ansprechen, nicht über die Bundle-ID (die findet macOS nicht zuverlässig).

4. **Get Name** leer lassen (Hookmark nimmt bei Datei-Links den Dateinamen).
5. Beim ersten ⌃H fragt macOS, ob Hookmark Finder-Ersatz steuern darf → **Erlauben**.

Danach öffnet ⌃H auf einer markierten Datei oder einem Ordner das Hookmark-Fenster wie im Finder.
Ohne Auswahl wird der aktuelle Ordner verwendet.

Test im Terminal: `osascript -e 'tell application "/Applications/Finder-Ersatz.app" to get selected paths'`
