import Foundation
import Network
import Observation

/// Ein per Bonjour gefundener Server im lokalen Netz (z. B. ein NAS).
struct NetworkServer: Identifiable, Hashable {
    enum Kind: String { case smb, afp }

    let name: String
    let kind: Kind
    var id: String { name }

    /// Adresse über den Bonjour-Dienstnamen, z. B. smb://NAS03._smb._tcp.local –
    /// funktioniert auch, wenn der Anzeigename vom Hostnamen abweicht.
    var url: URL? {
        let service = kind == .smb ? "_smb._tcp" : "_afpovertcp._tcp"
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
        return URL(string: "\(kind.rawValue)://\(encoded).\(service).local")
    }
}

/// Sucht fortlaufend nach SMB- und AFP-Servern im lokalen Netz.
@MainActor
@Observable
final class NetworkBrowser {
    private(set) var servers: [NetworkServer] = []

    @ObservationIgnored private var browsers: [NWBrowser] = []
    @ObservationIgnored private var found: [NetworkServer.Kind: Set<String>] = [:]

    func start() {
        guard browsers.isEmpty else { return }
        for kind in [NetworkServer.Kind.smb, .afp] {
            let type = kind == .smb ? "_smb._tcp" : "_afpovertcp._tcp"
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let names = Set(results.compactMap { result -> String? in
                    if case let .service(name, _, _, _) = result.endpoint { return name }
                    return nil
                })
                MainActor.assumeIsolated {
                    self?.update(kind: kind, names: names)
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }

    private func update(kind: NetworkServer.Kind, names: Set<String>) {
        found[kind] = names
        // Ein Gerät bietet oft SMB und AFP an: nur einmal anzeigen, SMB bevorzugen.
        let smb = found[.smb] ?? []
        let afp = (found[.afp] ?? []).subtracting(smb)
        servers = (smb.map { NetworkServer(name: $0, kind: .smb) } + afp.map { NetworkServer(name: $0, kind: .afp) })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
