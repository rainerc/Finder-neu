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
- `Model/` `FileItem`, `PaneState` (ein Fenster: Ordner, Verlauf, Auswahl, Sortierung), `BrowserState` (beide Fenster, aktives Fenster, Dateiaktionen)
- `Services/FileService` alle Dateisystem-Zugriffe (nur hier `FileManager` verwenden)
- `Views/` `ContentView` (Split + Aktionsleiste), `PaneView` (Kopf, Pfadleiste, Tabelle, Statuszeile)

## Konventionen
- UI-Texte deutsch, Code/Bezeichner englisch
- URLs immer über `normalizedFileURL` vergleichen (kein abschließender `/`)
- Neue Dateiaktionen: Logik in `FileService`, Aufruf über `BrowserState.run { }` (Fehler-Alert + Neuladen)

## Stand
- v0.1 MVP-Gerüst: Zwei-Fenster-Ansicht, Navigation, Pfadleiste, Favoriten, Sortierung, F5/F6 kopieren/verschieben, F2 umbenennen, neuer Ordner, Papierkorb, Drag & Drop, unsichtbare Dateien
- Baut auf Rainers Mac (macOS 26) ohne Fehler mit `swift run`

## Nächste Schritte
Siehe README „Nächste Schritte“. Priorität laut Rainer: Zwei-Fenster-Komfort zuerst.
