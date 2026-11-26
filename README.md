# Finder-Ersatz

Native macOS-App (SwiftUI, macOS 26 Tahoe) als komfortablerer Finder, angelehnt an Path Finder.
Kern des MVP: **Zwei-Fenster-Ansicht** (Dual Pane).

## Starten

**Schnell (ohne Xcode-Projekt):**
```sh
cd FinderErsatz
swift run
```

**Als richtige .app mit Signierung:**
```sh
brew install xcodegen
xcodegen            # erzeugt FinderErsatz.xcodeproj aus project.yml
open FinderErsatz.xcodeproj
```
In Xcode unter *Signing & Capabilities* das eigene Team wählen (oder `DEVELOPMENT_TEAM` in `project.yml` eintragen).
Die App-Sandbox ist bewusst aus, weil ein Dateimanager freien Zugriff braucht. Verteilt wird später per Developer ID + Notarisierung, nicht über den App Store.
Beim ersten Zugriff auf Schreibtisch, Dokumente usw. fragt macOS nach Erlaubnis. Für alles andere ggf. *Systemeinstellungen → Datenschutz → Festplattenvollzugriff*.

## Funktionen im MVP

| Funktion | Bedienung |
|---|---|
| Zwei Fenster nebeneinander, aktives Fenster farbig markiert | Klick oder `⌃⇥` / `⇥` zum Wechseln |
| Navigation zurück / vorwärts / hoch | `⌘[` `⌘]` `⌘↑`, Backspace = hoch |
| Seitenleiste mit eigenen Favoriten und Orten (Volumes) | Klick öffnet im aktiven Fenster |
| Favorit hinzufügen | `+` unten in der Seitenleiste, `⌃⌘T`, Kontextmenü oder Ordner in die Seitenleiste ziehen |
| Favoriten sortieren, umbenennen, entfernen | Ziehen bzw. Rechtsklick |
| Klickbare Pfadleiste | Fensterkopf |
| Sortierbare Spalten (Name, Datum, Größe, Art), Ordner zuerst | Spaltenkopf |
| Öffnen | Doppelklick / Return |
| In anderes Fenster kopieren / verschieben | `F5` / `F6` |
| Umbenennen | `F2` |
| Neuer Ordner | `⇧⌘N` |
| In den Papierkorb | `⌘⌫` |
| Drag & Drop zwischen Fenstern (gleiches Volume = verschieben) | Ziehen |
| Unsichtbare Dateien ein/aus | `⇧⌘.` |
| Fenster tauschen / anderes Fenster auf gleichen Ordner | `⌘U` / `⌘=` |
| Im Finder zeigen, Pfad kopieren | Kontextmenü |

Hinweis: F-Tasten brauchen auf Mac-Tastaturen ggf. `fn`.

## Aufbau

```
Sources/FinderErsatz/
  App/       FinderErsatzApp.swift  – App-Einstieg, Menüs, Tastenkürzel
  Model/     FileItem, PaneState (ein Fenster), BrowserState (beide Fenster + Aktionen)
  Services/  FileService            – alle Dateisystem-Operationen
  Views/     ContentView, PaneView  – Oberfläche
```

## Nächste Schritte (Ideen nach Path Finder)

1. Ordner live beobachten (FSEvents), statt nach Aktionen neu zu laden
2. Tabs pro Fenster
3. Vorschau-Leiste (Quick Look) und Info-Inspektor
4. Ordnergrößen berechnen, Filter/Suche im Fenster
5. Kopieren mit Fortschrittsanzeige und Warteschlange
6. Ordnervergleich und -synchronisation zwischen beiden Fenstern
7. Weitere Seitenleisten-Abschnitte (Tags, zuletzt benutzt, Netzwerk)
8. Terminal hier öffnen, Tags, Batch-Umbenennen
