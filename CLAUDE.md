# CLAUDE.md – Hinweise für Claude-Sessions

Projekt: nativer Finder-Ersatz für macOS 26 (Tahoe), angelehnt an Path Finder (cocoatech.io).
Kommunikation mit Rainer auf **Deutsch**. Diese Datei ist der Übergabepunkt zwischen Sessions/Accounts – nach größeren Änderungen „Stand“ und „Nächste Schritte“ aktualisieren.

## Technik
- Swift 6, SwiftUI (+ AppKit wo nötig), `@Observable`-Modelle auf `@MainActor`
- Bau: **`./scripts/build-app.sh`** (signierte .app in `build/`, empfohlen – TCC-Berechtigungen wie Netzwerkvolumes funktionieren nur mit echtem Bundle), `swift run` nur für schnelle Tests, oder `xcodegen && open FinderErsatz.xcodeproj` für eine signierte .app
- Berechtigungen (TCC): `build-app.sh` signiert immer mit demselben Zertifikat (SHA-1) → Freigaben bleiben über Neubauten erhalten. Wenn „Netzwerkvolumes“ trotz Schalter verweigert wird: `tccutil reset SystemPolicyNetworkVolumes com.example.FinderErsatz` (und `SystemPolicyAllFiles`), neu bauen, neu erlauben
- Keine App-Sandbox (Dateimanager braucht Vollzugriff); Verteilung später per Developer ID + Notarisierung
- Keine externen Abhängigkeiten ohne Rücksprache
- Linux-Sessions können nicht kompilieren: Änderungen sorgfältig gegen die macOS-26-SDK-APIs prüfen und Rainer bitten, lokal zu bauen

## Struktur
- `App/` Einstieg, Menüs, Tastenkürzel (`BrowserCommands`)
- `Model/` `PaneGroup` (eine Seite mit Tabs), `FileOperationQueue`/`FileJob` (Hintergrund-Aufträge mit Fortschritt), `FileItem`, `FavoritesStore` (Seitenleisten-Favoriten, gespeichert in UserDefaults), `PaneState` (ein Fenster: Ordner, Verlauf, Auswahl, Sortierung), `BrowserState` (beide Fenster, aktives Fenster, Dateiaktionen)
- `Model/` `AppSettings` (Darstellung, eigene Tastenkürzel; UserDefaults), `Shortcuts` (`ShortcutAction` mit Standardkürzeln, `Shortcut`), `SearchQuery`
- `Model/NetworkBrowser` (Bonjour-Suche per NWBrowser nach _smb._tcp/_afpovertcp._tcp)
- `Services/` `FileSearch` (Name/Regex/Inhalt, `mdfind` für Spotlight), `ArchiveService` (ditto/zip/tar), `ProcessRunner` (Werkzeuge starten, abbrechbar)
- `Services/` `NetworkMounter` (Einhängen per NetFSMountURLAsync mit macOS-Anmelde-/Freigabedialog), `FileService` (schnelle Dateioperationen), `FileTransfer` (Kopieren/Verschieben mit Fortschritt, läuft per `Task.detached`), `DirectoryWatcher` (Live-Aktualisierung per DispatchSource), `AppLauncher` (Terminal)
- `Views/` `ContentView` (NavigationSplitView: Seitenleiste + zwei Fenster + Aktionsleiste), `SidebarView` (Favoriten, Cloud, Netzwerk, Orte/Volumes), `TabBar`, `JobsPanel`, `TransferSheet` (F5/F6-Dialog), `SearchBar`, `FileGridView` (Kurz/Miniaturen), `ThumbnailView`, `SettingsView`, `PaneView` (Kopf, Pfadleiste, Tabelle, Statuszeile)

## Konventionen
- UI-Texte deutsch, Code/Bezeichner englisch
- URLs immer über `normalizedFileURL` vergleichen (kein abschließender `/`)
- Schnelle Dateiaktionen: Logik in `FileService`, Aufruf über `BrowserState.run { }` (Fehler-Alert + Neuladen)
- Langsame Aktionen (Kopieren/Verschieben): `TransferItem`s bauen und über `BrowserState.enqueue` (Konfliktprüfung) an `FileOperationQueue` geben
- `browser.pane(side)` / `activePane` liefern immer den aktiven Tab der Seite
- Neue Menübefehle: Fall in `ShortcutAction` ergänzen (Titel, Standardkürzel) und in `BrowserCommands` per `item(.fall) { … }` einhängen – dann sind sie automatisch in den Einstellungen umbelegbar
- Während einer Suche ersetzt `PaneState.items` den Ordnerinhalt durch die Treffer (`activeSearch != nil`)

## Stand
- v0.1 MVP-Gerüst: Zwei-Fenster-Ansicht, Navigation, Pfadleiste, Favoriten, Sortierung, F5/F6 kopieren/verschieben, F2 umbenennen, neuer Ordner, Papierkorb, Drag & Drop, unsichtbare Dateien
- v0.2 Seitenleiste: eigene Favoriten (hinzufügen per +, ⌃⌘T, Kontextmenü oder Ordner hineinziehen; umbenennen, entfernen, sortieren per Ziehen), Orte mit Volumes und Auswerfen. Klick öffnet im aktiven Fenster
- v0.3 Paket 1 der Roadmap: Tabs, Kopier-Warteschlange mit Fortschritt/Abbrechen/Konfliktdialog, F5/F6-Dialog mit änderbarem Ziel und Namen, Live-Aktualisierung, Quick Look (Leertaste/F3), Terminal hier öffnen, Cloud-Ordner in der Seitenleiste. Baut auf dem Mac. ⌘W wird per NSEvent-Monitor im AppDelegate abgefangen (Menü-Shortcut kollidierte mit „Fenster schließen“). Offen aus Paket 1: eigener Hex-Viewer
- v0.4 Netzwerk-Abschnitt in der Seitenleiste (eingehängte Freigaben, `volumeIsLocal == false`), Trennen, Mit Server verbinden (⌘K, öffnet smb://… über NSWorkspace)
- v0.5 Server im lokalen Netz in „Netzwerk“ (Bonjour), Klick → NetFS-Mount → Freigabe öffnet im aktiven Fenster; ⌘K nutzt ebenfalls NetFS. `Support/Info.plist` (Local-Network-Berechtigung, NSBonjourServices) wird per Linker in die `swift run`-Binary eingebettet und von XcodeGen genutzt
- v0.6 Paket 2: Suche (⌘F), ZIP/Archive (packen, entpacken, als Ordner öffnen), Ansichten Liste/Kurz/Miniaturen (⌘1–3), Einstellungen (⌘,) mit eigenen Tastenkürzeln, Schriftgröße, Hell/Dunkel, Farben. Baut auf dem Mac
- v0.7 AppleScript-Schnittstelle (`Support/FinderErsatz.sdef`: `selected paths`, `current folder`, per `@objc`-Properties in einer `NSApplication`-Extension, Zugriff über `BrowserState.current`) für Hookmark ⌃H – funktioniert bei Rainer mit dem AppleScript aus `docs/HOOKMARK.md`. Fallstricke: `BrowserState.current` erst in `ContentView.onAppear` setzen (SwiftUI erzeugt `@State`-Startwerte mehrfach); App im Skript per Pfad ansprechen; Diagnose per `get debug info`. Zusätzlich meldet das Fenster das ausgewählte Objekt als `representedURL`
- v0.8 Spalten wählbar (Rechtsklick auf Spaltenkopf): `TableColumnCustomization` mit `customizationID`, gespeichert per `@AppStorage("tableColumns")` (beide Fenster gemeinsam). Neue `FileItem`-Felder: created, accessed, fileExtension, tags, permissions, owner. Max. 10 Spalten pro TableColumnBuilder-Block
- v0.1 baut auf Rainers Mac (macOS 26) ohne Fehler mit `swift run`

## Nächste Schritte
Siehe `docs/ROADMAP.md` (Abgleich mit Commander One, Pakete 1–3). Priorität laut Rainer: Zwei-Fenster-Komfort zuerst.
