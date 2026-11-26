# CLAUDE.md – Hinweise für Claude-Sessions

Projekt: nativer Finder-Ersatz für macOS 26 (Tahoe), angelehnt an Path Finder (cocoatech.io).
Kommunikation mit Rainer auf **Deutsch**. Diese Datei ist der Übergabepunkt zwischen Sessions/Accounts – nach größeren Änderungen „Stand“ und „Nächste Schritte“ aktualisieren.

## Technik
- Swift 6, SwiftUI (+ AppKit wo nötig), `@Observable`-Modelle auf `@MainActor`
- Bau: **`./scripts/build-app.sh`** (signierte .app in `build/`, empfohlen – TCC-Berechtigungen wie Netzwerkvolumes funktionieren nur mit echtem Bundle), `swift run` nur für schnelle Tests, oder `xcodegen && open FinderErsatz.xcodeproj` für eine signierte .app
- Berechtigungen (TCC): `build-app.sh` signiert immer mit demselben Zertifikat (SHA-1) → Freigaben bleiben über Neubauten erhalten. Wenn „Netzwerkvolumes“ trotz Schalter verweigert wird: `tccutil reset SystemPolicyNetworkVolumes com.example.FinderErsatz` (und `SystemPolicyAllFiles`), neu bauen, neu erlauben
- Diagnose bei Berechtigungsproblemen: `./scripts/check-permissions.sh` vergleicht die Signatur der installierten App mit der in der TCC-Datenbank gespeicherten Anforderung (csreq) – zeigt, ob der Eintrag fehlt, verweigert ist oder die Signatur nicht passt. `build-app.sh` merkt sich das Zertifikat in `.signing-identity` (nicht im Git) und warnt, wenn sich das Designated Requirement gegenüber dem letzten Bau ändert (`build/.last-dr`). Empfehlung: Festplattenvollzugriff erteilen (deckt Netzwerkvolumes mit ab)
- **Ursache des „Comics“-Fehlers (v0.10):** Es lief nicht die installierte App, sondern `.build/debug/FinderErsatz` (Test-Build ohne Bundle, z. B. aus einem alten Kurzbefehl mit `swift build && .build/debug/FinderErsatz`). Für diese Binary gelten die TCC-Freigaben nicht. Die App zeigt deshalb jetzt oben einen Warnhinweis mit „Installierte App starten“, wenn `Bundle.main.bundleURL` kein `.app` ist (`AppEnvironment.isRunningUnbundled`), und `build-app.sh` beendet auch Test-Builds. Immer `/Applications/Finder-Ersatz.app` starten
- Keine App-Sandbox (Dateimanager braucht Vollzugriff); Verteilung später per Developer ID + Notarisierung
- Keine externen Abhängigkeiten ohne Rücksprache
- Linux-Sessions können nicht kompilieren: Änderungen sorgfältig gegen die macOS-26-SDK-APIs prüfen und Rainer bitten, lokal zu bauen

## Struktur
- `App/` Einstieg, Menüs, Tastenkürzel (`BrowserCommands`)
- `Model/` `PaneGroup` (eine Seite mit Tabs), `FileOperationQueue`/`FileJob` (Hintergrund-Aufträge mit Fortschritt), `FileItem`, `FavoritesStore` (Seitenleisten-Favoriten, gespeichert in UserDefaults), `PaneState` (ein Fenster: Ordner, Verlauf, Auswahl, Sortierung), `BrowserState` (beide Fenster, aktives Fenster, Dateiaktionen)
- `Model/` `AppSettings` (Darstellung, eigene Tastenkürzel; UserDefaults), `Shortcuts` (`ShortcutAction` mit Standardkürzeln, `Shortcut`), `SearchQuery`
- `Model/SmartFolders` (`SmartFolderStore`: gespeicherte Suchen für die Seitenleiste)
- `Model/NetworkBrowser` (Bonjour-Suche per NWBrowser nach _smb._tcp/_afpovertcp._tcp)
- `Services/` `FileSearch` (Name/Regex/Inhalt, `mdfind` für Spotlight), `ArchiveService` (ditto/zip/tar), `ProcessRunner` (Werkzeuge starten, abbrechbar)
- `Services/` `NetworkMounter` (Einhängen per NetFSMountURLAsync mit macOS-Anmelde-/Freigabedialog), `FileService` (schnelle Dateioperationen), `FileTransfer` (Kopieren/Verschieben mit Fortschritt, läuft per `Task.detached`), `DirectoryWatcher` (Live-Aktualisierung per DispatchSource), `AppLauncher` (Terminal)
- `Views/` `ColumnBrowserView`, `GalleryView`, `InspectorView` (Stapel B), `BatchRenameSheet` (Stapel C), `ContentView` (NavigationSplitView: Seitenleiste + zwei Fenster + Aktionsleiste), `SidebarView` (Favoriten, Cloud, Netzwerk, Orte/Volumes), `TabBar`, `JobsPanel`, `TransferSheet` (F5/F6-Dialog), `SearchBar`, `FileGridView` (Kurz/Miniaturen), `ThumbnailView`, `SettingsView`, `PaneView` (Kopf, Pfadleiste, Tabelle, Statuszeile)

## Konventionen
- UI-Texte deutsch, Code/Bezeichner englisch
- URLs immer über `normalizedFileURL` vergleichen (kein abschließender `/`)
- Schnelle Dateiaktionen: Logik in `FileService`, Aufruf über `BrowserState.run { }` (Fehler-Alert + Neuladen)
- Langsame Aktionen (Kopieren/Verschieben): `TransferItem`s bauen und über `BrowserState.enqueue` (Konfliktprüfung) an `FileOperationQueue` geben
- `browser.pane(side)` / `activePane` liefern immer den aktiven Tab der Seite
- Neue Menübefehle: Fall in `ShortcutAction` ergänzen (Titel, Standardkürzel) und in `BrowserCommands` per `item(.fall) { … }` einhängen – dann sind sie automatisch in den Einstellungen umbelegbar
- Neue Dateiaktionen, die etwas verändern, mit `recordUndo(...)` widerrufbar machen
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
- v0.9 Finder-Stapel A: Zwischenablage (Bearbeiten-Menü ersetzt; in Textfeldern `NSApp.sendAction` an den First Responder, sonst Dateiaktion), Duplizieren, Alias, Öffnen mit, Paketinhalt, Gehe zu Ordner, Informationen (`InfoSheet`), Farb-Tags (`FinderTags.swift`, `TagDots`), Teilen (`ShareLink`), Widerrufen (`UndoStack.swift`, `browser.recordUndo`). Noch nicht auf dem Mac gebaut
- v0.9 auf dem Mac bestätigt. ⌥-Kürzel (⌥⌘C) im AppDelegate-Monitor abgefangen, weil das SwiftUI-Menü sie auf deutscher Tastatur nicht erkennt; `browser.flash(...)` zeigt kurze Rückmeldung in der Aktionsleiste; Kontextmenü „als Pfadname kopieren“ per `modifierKeyAlternate(.option)` (bestätigt)
- v0.10 Stapel B: Spaltenansicht (`ColumnBrowserView`, ⌘4: Klick in eine Spalte macht deren Ordner zum aktuellen Ordner + Auswahl), Galerie (`GalleryView`, ⌘5), Vorschau-Spalte (`InspectorView`, ⇧⌘P, `.inspector`, QLPreviewView + MDItem-Metadaten), Ordnergrößen (`AppSettings.calculateFolderSizes`, `PaneState.applyFolderSizes` mit Cache, nur lokale Volumes). Noch nicht auf dem Mac gebaut
- v0.11 Stapel C: Seitenleisten-Abschnitte „Intelligente Ordner“ (Zuletzt benutzt + gespeicherte Suchen, `SmartFolderStore`) und „Tags“. Technik: `SearchQuery` hat `title`, `spotlightQuery` (rohe mdfind-Abfrage) und `sidebarTag` (`finderersatz://recents|tag/…|smart/…`, markiert den Eintrag; Auswahl-Binding in `SidebarView.open`); Anzeige läuft über `PaneState.startSearch(_:sortOrder:)` (Sortierung wird danach wiederhergestellt). Stapel-Umbenennen: `BatchRenameSheet`, `BrowserState.applyBatchRename` (zweistufig über vorläufige Namen, Undo als `.moved`). Noch nicht auf dem Mac gebaut
- v0.11 zusätzlich: „Neuer Tab“-Knopf im Fensterkopf bei nur einem Tab; Vorschaubereich unten in jedem Fenster (`PanePreview` in `InspectorView.swift`, `VSplitView` in `PaneView`, `browser.showPanePreview`, ⌃⌘P)
- Schnellansicht nutzt jetzt das native `QLPreviewPanel` (`Services/QuickLookController.swift`, hängt sich in die Responder-Kette des Fensters, folgt der Auswahl, Pfeiltasten werden ans Fenster weitergereicht) statt SwiftUIs `.quickLookPreview` – das brauchte bei Ordnern sehr lange
- Leertaste auf einem Ordner zeigt die eigene schnelle Vorschau (`FolderPreviewSheet`, eine Ebene). Grund: XRay durchsucht den ganzen Ordnerbaum (bei Rainer ~/Documents: 4,79 GB, 18.151 Objekte) und braucht selbst mit `qlmanage -p` ewig. Quick Look/XRay für Ordner: Einstellung `folderPreviewUsesQuickLook`, ⇧-Leertaste, ⌘Y (umbelegbar) oder Knopf im Sheet; ⌥-Leertaste ging nicht (Alfred) (Rainers Wahl)
- Regex-Assistent (`RegexHelperSheet`, nach dem Vorbild von regex101: links Muster mit Syntaxfarben/Ersetzung/editierbare Testnamen mit farbigen Gruppen, rechts Erklärung (`RegexSyntax.tokens`), Treffer-Details mit Positionen, durchsuchbare Kurzreferenz): in der Suchleiste (Modus Regex, Zauberstab) und im Stapel-Umbenennen (Modus „Regex“ mit $1-Ersetzung). Bausteine, Vorlagen, Muster aus Beispielnamen ableiten (`RegexInference`), deutsche Erklärung, Live-Test mit Markierung, Gruppen und Umbenennungs-Vorschau. Alles lokal, kein externer Dienst
- v0.1 baut auf Rainers Mac (macOS 26) ohne Fehler mit `swift run`

## Übergabe an eine neue Session / einen anderen Claude-Account
- **Repo:** GitHub `rainerc/Finder-neu` (Branch `main`, es wird direkt auf `main` gepusht – so mit Rainer vereinbart). Der neue Account braucht GitHub-Zugriff (claude.ai → GitHub verbinden, Claude-GitHub-App für das Repo installiert). Diese Datei zuerst lesen.
- **Rainers Mac:** Projekt liegt unter `~/finder-neu`. Bauen/Installieren immer mit `cd ~/finder-neu && git pull && ./scripts/build-app.sh` (installiert nach `/Applications/Finder-Ersatz.app` und startet). **Nie** `swift run` / `.build/debug/FinderErsatz` zum Arbeiten starten – dafür gelten keine Berechtigungen (App zeigt dann einen orangen Hinweis)
- **Neustart per Apple-Kurzbefehl:** Kurzbefehl soll `pkill -x FinderErsatz; open /Applications/Finder-Ersatz.app` ausführen (nicht die Debug-Binary)
- **Signieren/Berechtigungen:** fest gemerktes „Apple Development“-Zertifikat (`.signing-identity`), Festplattenvollzugriff für `/Applications/Finder-Ersatz.app` ist erteilt. Bei Problemen `./scripts/check-permissions.sh` (Terminal braucht dafür Festplattenvollzugriff)
- **Hookmark (⌃H):** siehe `docs/HOOKMARK.md` (AppleScript, App per Pfad ansprechen) – funktioniert
- **XRay:** Quick-Look-Erweiterung, die bei Ordnern den ganzen Baum durchsucht (bei Rainer ~5 Minuten für ~/Documents, auch im Finder/`qlmanage`). Deshalb eigene Ordnervorschau auf der Leertaste, XRay per ⇧-Leertaste/⌘Y
- **Tastenkürzel mit ⌥** funktionieren im SwiftUI-Menü auf deutscher Tastatur nicht zuverlässig → im `AppDelegate`-Keymonitor abfangen (wie ⌥⌘C). ⌥-Leertaste ist bei Rainer von Alfred belegt
- **Arbeitsweise mit Rainer:** Deutsch, kurze Antworten; nach jeder Änderung pushen und ihn bitten zu bauen; Baufehler schickt er als Terminal-Ausgabe. Linux-Sessions können nicht kompilieren – SwiftUI/AppKit-APIs sorgfältig prüfen (typische Stolpersteine bisher: `onKeyPress(.space) { press in }` gibt es nicht → `onKeyPress(keys: [.space]) { press in }`; Swift-6-Isolation bei AppKit-Delegates)

## Nächste Schritte
- **Noch nicht von Rainer bestätigt:** Stapel B (Spalten, Galerie, Vorschau-Spalte, Ordnergrößen), Stapel C (Zuletzt benutzt, Tags, intelligente Ordner, Stapel-Umbenennen), Vorschaubereich unten, native Schnellansicht + Ordnervorschau, Regex-Assistent (regex101-Stil). Zuerst Rückmeldung/Baufehler dazu abarbeiten
- **Stapel D (Finder-Abgleich, `docs/ROADMAP.md`):** federnde Ordner, Dienste/Schnellaktionen, Symbolleiste anpassen, iCloud-Status (laden/entfernen), Fenster/Tabs beim Neustart wiederherstellen, Papierkorb anzeigen/entleeren/„Zurücklegen“
- **Paket 3 (Commander-One-Abgleich):** SFTP/WebDAV, Prozess-Manager, Cloud-APIs – erst nach Rücksprache
- Offen aus Paket 1: eigener Hex-Viewer
- Priorität laut Rainer: Zwei-Fenster-Komfort zuerst
