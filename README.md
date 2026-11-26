# Finder-Ersatz

Native macOS-App (SwiftUI, macOS 26 Tahoe) als komfortablerer Finder, angelehnt an Path Finder.
Kern des MVP: **Zwei-Fenster-Ansicht** (Dual Pane).

## Starten

**Empfohlen – als echte App (Berechtigungen funktionieren zuverlässig):**
```sh
./scripts/build-app.sh
```
Baut `build/Finder-Ersatz.app`, signiert sie mit deinem Apple-Development-Zertifikat und startet sie. Die App kannst du auch nach `/Programme` kopieren.

**Nur zum schnellen Testen** (ohne Bundle – macOS-Berechtigungen, z. B. für Netzwerkvolumes, greifen hier nicht zuverlässig):
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

Beim ersten Start fragt macOS, ob die App auf das lokale Netzwerk zugreifen darf – das ist für die Serversuche nötig.

## Funktionen im MVP

| Funktion | Bedienung |
|---|---|
| Zwei Fenster nebeneinander, aktives Fenster farbig markiert | Klick, `⇥` oder `⌥⇥` zum Wechseln |
| Tabs pro Fenster | `⌘T` neu, `⌘W` schließen (der letzte Tab bleibt offen), `⌃⇥` / `⌃⇧⇥` wechseln, Kontextmenü „In neuem Tab öffnen“ |
| Schnellansicht (Quick Look, nutzt installierte Erweiterungen wie XRay) | Leertaste oder `F3` |
| Suche ab aktuellem Ordner: Name enthält / Platzhalter (`*.jpg; *.png`) / Regex / Spotlight, Groß-/Kleinschreibung, Inhaltssuche mit Kodierung | `⌘F`, Lupe im Fensterkopf |
| Ansichten Liste, Kurz (mehrspaltig), Miniaturen (Vorschaubilder) | `⌘1` / `⌘2` / `⌘3` oder Umschalter im Fensterkopf |
| Als ZIP komprimieren; entpacken (zip, tar.gz, tar.bz2, tar.xz, 7z, rar …) hierher oder ins andere Fenster | Kontextmenü, Menü „Ablage-Aktionen“ |
| Archiv wie Ordner öffnen (entpackte Kopie) | Doppelklick auf Archiv |
| Hookmark (⌃H) auf Dateien und Ordnern – Einrichtung siehe `docs/HOOKMARK.md` | `⌃H` |
| Einstellungen: eigene Tastenkürzel, Schriftgröße, Hell/Dunkel, Farben | `⌘,` |
| Ordner aktualisieren sich automatisch | – |
| Terminal im aktuellen Ordner | `⌥⌘T` oder Kontextmenü |
| Netzwerk: Server im lokalen Netz (Bonjour, SMB/AFP) – Klick verbindet und öffnet die Freigabe; eingehängte Freigaben, Trennen per Rechtsklick | Mit Server verbinden: `⌘K` |
| Cloud-Ordner (iCloud Drive, Dropbox, Google Drive, OneDrive …) | Seitenleiste „Cloud“ |
| Navigation zurück / vorwärts / hoch | `⌘[` `⌘]` `⌘↑`, Backspace = hoch |
| Seitenleiste mit eigenen Favoriten und Orten (Volumes) | Klick öffnet im aktiven Fenster |
| Favorit hinzufügen | `+` unten in der Seitenleiste, `⌃⌘T`, Kontextmenü oder Ordner in die Seitenleiste ziehen |
| Favoriten sortieren, umbenennen, entfernen | Ziehen bzw. Rechtsklick |
| Klickbare Pfadleiste | Fensterkopf |
| Sortierbare Spalten (Name, Datum, Größe, Art), Ordner zuerst | Spaltenkopf |
| Öffnen | Doppelklick / Return |
| In anderes Fenster kopieren / verschieben (Dialog: Ziel und Name änderbar) | `F5` / `F6` |
| Hintergrund-Warteschlange mit Fortschritt und Abbrechen, Konfliktdialog (Ersetzen / Beide behalten / Überspringen) | automatisch |
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
