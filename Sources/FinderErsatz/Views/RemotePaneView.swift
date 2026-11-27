import SwiftUI
import AppKit

/// Inhalt eines Dateifensters, das einen FTP/SFTP-Server zeigt.
/// F5/F6 kopieren/verschieben ins andere Fenster, F7 neuer Ordner, F8 löschen, F2 umbenennen (siehe `RemotePane.swift`).
struct RemotePaneView: View {
    @Environment(BrowserState.self) private var browser
    @Bindable var remote: RemoteBrowser
    let pane: PaneState
    let side: PaneSide

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { browser.activeSide = side }
                )
            Divider()
            table
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if remote.entries.isEmpty, !remote.isBusy, remote.errorText == nil {
                        Text("Leerer Ordner").foregroundStyle(.secondary)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    let files = urls.filter(\.isFileURL)
                    guard !files.isEmpty else { return false }
                    browser.upload(files, from: browser.otherPane, to: remote, move: false)
                    return true
                }
            Divider()
            statusBar
        }
        .onChange(of: remote.selection) { browser.activeSide = side }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button("Zurück", systemImage: "chevron.left") { remote.goBack() }
                .disabled(!remote.canGoBack || remote.isBusy)
            Button("Nach oben", systemImage: "arrow.up") { remote.goUp() }
                .disabled(!remote.canGoUp || remote.isBusy)
            Image(systemName: remote.connection.kind == .sftp ? "lock.shield" : "network")
                .foregroundStyle(.secondary)
            Text(remote.path)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(minWidth: 30, alignment: .leading)
            Spacer(minLength: 0)
            if remote.isBusy { ProgressView().controlSize(.small) }
            Button("Aktualisieren", systemImage: "arrow.clockwise") { Task { await remote.reload() } }
                .disabled(remote.isBusy)
            Button("Neuer Ordner", systemImage: "folder.badge.plus") {
                browser.activeSide = side
                browser.remoteNewFolder(remote)
            }
            Button("Trennen", systemImage: "eject") { browser.closeRemote(in: pane) }
                .help("Verbindung trennen und wieder den Ordner auf dem Mac zeigen")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private var table: some View {
        Table(remote.entries, selection: $remote.selection) {
            TableColumn("Name") { entry in
                Label(entry.name, systemImage: entry.isDirectory ? "folder.fill" : (entry.isLink ? "link" : "doc"))
            }
            TableColumn("Größe") { entry in
                Text(entry.isDirectory ? "--" : entry.size.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Geändert") { entry in
                Text(entry.modified?.formatted(date: .numeric, time: .shortened) ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 140)
        }
        .contextMenu(forSelectionType: RemoteEntry.ID.self) { ids in
            if !ids.isEmpty {
                Button(browser.otherPane.remote == nil
                       ? "Ins andere Fenster laden (F5)" : "Ins andere Fenster laden") {
                    remote.selection = ids
                    browser.activeSide = side
                    browser.copyToOtherPane()
                }
                Button("Ins andere Fenster verschieben (F6)") {
                    remote.selection = ids
                    browser.activeSide = side
                    browser.moveToOtherPane()
                }
                Divider()
                Button("Umbenennen …") {
                    remote.selection = ids
                    browser.activeSide = side
                    browser.remoteRename(remote)
                }
                .disabled(ids.count != 1)
                Button("Pfad kopieren") {
                    let paths = remote.entries.filter { ids.contains($0.id) }.map { remote.fullPath($0) }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
                }
                Divider()
                Button("Löschen …", role: .destructive) {
                    remote.selection = ids
                    browser.activeSide = side
                    browser.remoteDelete(remote)
                }
            } else {
                Button("Neuer Ordner …") { browser.remoteNewFolder(remote) }
                Button("Aktualisieren") { Task { await remote.reload() } }
            }
        } primaryAction: { ids in
            guard ids.count == 1, let entry = remote.entries.first(where: { $0.id == ids.first }) else { return }
            if entry.isDirectory || entry.isLink {
                remote.open(entry)
            } else {
                browser.activeSide = side
                browser.copyToOtherPane()
            }
        }
        .onKeyPress(keys: [.delete]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            remote.goUp()
            return .handled
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            if let error = remote.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Erneut") { Task { await remote.start() } }
                    .buttonStyle(.borderless)
            } else {
                Text(remote.selection.isEmpty ? remote.status : "\(remote.selection.count) von \(remote.entries.count) ausgewählt")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("F5/F6: ins andere Fenster · Hineinziehen: hochladen")
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
