# Roadmap: Funktionen nach Vorbild Commander One

Quelle: Funktionsliste von Commander One (Eltima, mac.eltima.com/commander-one) und Wikipedia, Stand November 2026.
Legende: ✅ vorhanden · 🟡 teilweise · ⬜ fehlt. Aufwand: S (Stunden), M (1–2 Tage), L (mehrere Tage).

## Abgleich mit unserer App

| Bereich | Commander One | Unsere App | Aufwand |
|---|---|---|---|
| Zwei Fenster | ✔ | ✅ | – |
| Tabs pro Fenster (unbegrenzt) | ✔ | ⬜ | M |
| Ansichten: Voll / Kurz (mehrspaltig) / Miniaturen | ✔ | 🟡 nur Liste | M |
| Verlauf, Favoriten | ✔ | ✅ | – |
| Unsichtbare Dateien ein/aus | ✔ | ✅ | – |
| Mehrfachauswahl, Kopieren/Verschieben/Löschen/Umbenennen | ✔ | ✅ | – |
| Warteschlange für Dateioperationen mit Fortschritt | ✔ | ⬜ (läuft synchron) | M |
| Umbenennen beim Kopieren/Verschieben, Konfliktdialog | ✔ | ⬜ (automatisch „Name 2“) | S–M |
| Eingebauter Viewer (Text, Bild, Medien, HTML, Hex) | ✔ | ⬜ | M (Quick Look + Hex-Ansicht) |
| Suche: Name mit Regex, Groß/klein, Inhaltssuche, Spotlight | ✔ | ⬜ | M |
| ZIP packen/entpacken, Archiv wie Ordner öffnen | ✔ | ⬜ | M (über `ditto`/`tar`, ohne Fremdbibliothek) |
| RAR, 7z, TarGz | Pro | ⬜ | L (7z/RAR brauchen Bibliothek) |
| Eigene Tastenkürzel | ✔ | 🟡 fest vorgegeben | M |
| Schriften, Farben, Themes | ✔ / Pro | ⬜ | M |
| Lokales Netzwerk, Netzlaufwerke | ✔ | 🟡 Volumes in „Orte“ | M |
| Eingebautes Terminal | Pro | ⬜ | S für „Terminal hier öffnen“, L für eingebettetes Terminal |
| Prozess-Manager | Pro | ⬜ | M |
| FTP/SFTP/FTPS/WebDAV, Passwörter im Schlüsselbund | Pro | ⬜ | L |
| Cloud: Dropbox, Google Drive, OneDrive, S3, Box, B2 | Pro | ⬜ | S für macOS-Cloud-Ordner (`~/Library/CloudStorage`) in der Seitenleiste, L für eigene API-Anbindung |
| Root-Zugriff | ✔ | ⬜ | L (privilegierter Helfer, sicherheitskritisch) |
| iOS-/Android-/MTP-Geräte | Pro | ⬜ | L (nicht empfohlen) |
| Finder-Erweiterungen | ✔ | ⬜ | L |

## Vorschlag zur Reihenfolge

**Paket 1: Zwei-Fenster-Komfort** – umgesetzt in v0.3 (außer Hex-Viewer)
1. Tabs pro Fenster (⌘T, ⌘W, ⌃⇥)
2. Warteschlange für Kopieren/Verschieben mit Fortschritt und Abbrechen, Konfliktdialog (Ersetzen / Überspringen / Beide behalten) und Umbenennen beim Kopieren
3. Ordner live aktualisieren (FSEvents)
4. Schnellansicht mit Leertaste/F3 (Quick Look) und Text-/Hex-Viewer
5. „Terminal hier öffnen“, Cloud-Ordner von macOS in der Seitenleiste

**Paket 2: Suchen, Archive, Ansichten** – umgesetzt in v0.6
6. Suche nach Name (Platzhalter/Regex, Groß/klein) und Inhalt, plus Spotlight
7. ZIP packen/entpacken, ZIP wie Ordner durchsuchen
8. Ansichten „Kurz“ (mehrspaltig) und „Miniaturen“
9. Eigene Tastenkürzel, Schriften und Farben

**Paket 3: Netzwerk und Profi-Funktionen (größerer Aufwand)**
10. Netzwerk-Browser (Bonjour/SMB)
11. SFTP/FTP/WebDAV mit Schlüsselbund
12. Prozess-Manager
13. Cloud-Dienste per eigener API, Root-Zugriff, weitere Archivformate

Bewusst zurückgestellt: iOS-/Android-/MTP-Geräte (sehr aufwändig, kaum Nutzen gegenüber macOS-eigenen Wegen).

---

# Abgleich mit dem macOS-Finder (Wunsch: alle Finder-Funktionen)

Stand November 2026. ✅ vorhanden · ⬜ fehlt · ✖ technisch nicht möglich

| Finder-Funktion | Status |
|---|---|
| Listen-, Symbol-(Miniaturen-)Ansicht | ✅ |
| Spaltenansicht (Miller Columns) | ✅ Stapel B |
| Galerie-Ansicht | ✅ Stapel B |
| Vorschau-Spalte / Inspektor mit Metadaten | ✅ Stapel B |
| Tabs, Seitenleiste, Favoriten, Pfadleiste, Statusleiste | ✅ |
| Quick Look (Leertaste) | ✅ |
| Suche, Spotlight | ✅ |
| Komprimieren / Entpacken | ✅ |
| Kopieren ⌘C / Einsetzen ⌘V / Bewegen ⌥⌘V | ✅ Stapel A |
| Duplizieren ⌘D, Alias erstellen ⌃⌘A | ✅ Stapel A |
| Öffnen mit … | ✅ Stapel A |
| Informationen ⌘I (Größe inkl. Ordnergröße, Daten, Pfad, Tags, Rechte) | ✅ Stapel A |
| Gehe zu Ordner ⇧⌘G | ✅ Stapel A |
| Tags & Farben setzen und anzeigen | ✅ Stapel A |
| Teilen (inkl. AirDrop, Mail, Nachrichten) | ✅ Stapel A |
| Paketinhalt zeigen | ✅ Stapel A |
| Pfad kopieren ⌥⌘C | ✅ Stapel A |
| Widerrufen ⌘Z (Umbenennen, Verschieben, Papierkorb, neuer Ordner) | ✅ Stapel A |
| Ordnergrößen berechnen | ✅ Stapel B |
| Zuletzt benutzt (Recents) | ⬜ Stapel C |
| Tags in der Seitenleiste (Dateien je Tag) | ⬜ Stapel C |
| Intelligente Ordner / gespeicherte Suchen | ⬜ Stapel C |
| Stapel-Umbenennen (Text ersetzen, Nummerieren, Format) | ⬜ Stapel C |
| Federnde Ordner (beim Ziehen öffnen) | ⬜ Stapel D |
| Dienste / Schnellaktionen | ⬜ Stapel D |
| Symbolleiste anpassen | ⬜ Stapel D |
| iCloud-Status (geladen / nur in der Cloud), Laden/Entfernen | ⬜ Stapel D |
| Fenster/Tabs beim Neustart wiederherstellen | ⬜ Stapel D |
| Papierkorb anzeigen / entleeren, „Zurücklegen“ | ⬜ Stapel D |
| Sync-Symbole von Dropbox & Co. (Finder-Sync-Erweiterungen) | ✖ nur im Finder selbst |
| CDs/DVDs brennen | ✖ veraltet, nicht vorgesehen |

**Stapel A – Alltag** (umgesetzt in v0.9): Kopieren/Einsetzen/Bewegen über die Zwischenablage, Duplizieren, Alias, Öffnen mit, Informationen, Gehe zu Ordner, Tags & Farben, Teilen/AirDrop, Paketinhalt, Pfad kopieren, Widerrufen.
**Stapel B – Ansichten** (umgesetzt in v0.10): Spaltenansicht, Galerie, Vorschau/Inspektor, Ordnergrößen.
**Stapel C – Organisieren:** Zuletzt benutzt, Tags in der Seitenleiste, intelligente Ordner, Stapel-Umbenennen.
**Stapel D – Feinschliff:** Federnde Ordner, Dienste, Symbolleiste, iCloud-Status, Fenster wiederherstellen, Papierkorb.
