import Foundation
import NetFS

/// Hängt Netzwerkfreigaben ein. macOS zeigt dabei selbst den Anmeldedialog
/// und – wenn die Adresse keine Freigabe enthält – die Auswahl der Freigaben.
enum NetworkMounter {
    /// Ruft `completion` auf dem Main-Thread mit den eingehängten Pfaden auf
    /// (leer bei Abbruch) oder mit einer Fehlermeldung.
    @MainActor
    static func mount(_ url: URL, completion: @escaping @MainActor @Sendable ([URL], String?) -> Void) {
        let openOptions = NSMutableDictionary()
        openOptions["UIOption"] = "AllowUI"          // kNAUIOptionKey = kNAUIOptionAllowUI
        let mountOptions = NSMutableDictionary()

        var requestID: AsyncRequestID?
        let status = NetFSMountURLAsync(
            url as CFURL, nil, nil, nil,
            openOptions as CFMutableDictionary, mountOptions as CFMutableDictionary,
            &requestID, DispatchQueue.main
        ) { status, _, mountpoints in
            let paths = (mountpoints.map { $0 as NSArray } as? [String]) ?? []
            let urls = paths.map { URL(filePath: $0) }
            // ECANCELED (89) bzw. userCanceledErr (-128): Benutzer hat abgebrochen.
            let message: String? = (status == 0 || status == ECANCELED || status == -128)
                ? nil
                : "Verbindung zu „\(url.host ?? url.absoluteString)“ fehlgeschlagen (Fehler \(status))."
            MainActor.assumeIsolated {
                completion(urls, message)
            }
        }
        if status != 0 {
            completion([], "Verbindung zu „\(url.host ?? url.absoluteString)“ konnte nicht gestartet werden (Fehler \(status)).")
        }
    }
}
