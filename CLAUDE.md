# CLAUDE.md – Hinweise für Claude-Sessions

Projekt: nativer Finder-Ersatz für macOS 26 (Tahoe), angelehnt an Path Finder (cocoatech.io).
Kommunikation mit Rainer auf **Deutsch**. Diese Datei ist der Übergabepunkt zwischen Sessions/Accounts – nach größeren Änderungen „Stand“ und „Nächste Schritte“ aktualisieren.

## Technik
- Swift 6, SwiftUI (+ AppKit wo nötig), `@Observable`-Modelle auf `@MainActor`
- Bau: `swift run` (Swift Package) oder `xcodegen && open FinderErsatz.xcodeproj` für eine signierte .app
- Keine App-Sandbox (Dateimanager braucht Vollzugriff); Verteilung später per Developer ID + Notarisierung
- Keine externen Abhängigkeiten ohne Rücksprache
- Linux-Sessions können nicht kompilieren: Änderungen sorgfältig gegen die macOS-26-SDK-APIs prüfen und Rainer bitten, lokal zu bauen

## Struktur
- `App/` Einstieg, Menüs, Tastenkürzel (`BrowserCommands`)
- `Model/` `FileItem`, `FavoritesStore` (Seitenleisten-Favoriten, gespeichert in UserDefaults), `PaneState` (ein Fenster: Ordner, Verlauf, Auswahl, Sortierung), `BrowserState` (beide Fenster, aktives Fenster, Dateiaktionen)
- `Services/FileService` alle Dateisystem-Zugriffe (nur hier `FileManager` verwenden)
- `Views/` `ContentView` (NavigationSplitView: Seitenleiste + zwei Fenster + Aktionsleiste), `SidebarView` (Favoriten, Orte/Volumes), `PaneView` (Kopf, Pfadleiste, Tabelle, Statuszeile)

## Konventionen
- UI-Texte deutsch, Code/Bezeichner englisch
- URLs immer über `normalizedFileURL` vergleichen (kein abschließender `/`)
- Neue Dateiaktionen: Logik in `FileService`, Aufruf über `BrowserState.run { }` (Fehler-Alert + Neuladen)

## Stand
- v0.1 MVP-Gerüst: Zwei-Fenster-Ansicht, Navigation, Pfadleiste, Favoriten, Sortierung, F5/F6 kopieren/verschieben, F2 umbenennen, neuer Ordner, Papierkorb, Drag & Drop, unsichtbare Dateien
- v0.2 Seitenleiste: eigene Favoriten (hinzufügen per +, ⌃⌘T, Kontextmenü oder Ordner hineinziehen; umbenennen, entfernen, sortieren per Ziehen), Orte mit Volumes und Auswerfen. Klick öffnet im aktiven Fenster
- v0.1 baut auf Rainers Mac (macOS 26) ohne Fehler mit `swift run`

## Nächste Schritte
Siehe `docs/ROADMAP.md` (Abgleich mit Commander One, Pakete 1–3). Priorität laut Rainer: Zwei-Fenster-Komfort zuerst.
