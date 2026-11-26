import AppKit

/// Öffnet Bereiche der Systemeinstellungen (Datenschutz & Sicherheit).
enum SystemSettings {
    enum Pane: String {
        case fullDiskAccess = "Privacy_AllFiles"
        case filesAndFolders = "Privacy_FilesAndFolders"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
