import SwiftUI

/// Dialog für F5/F6: Ziel bestätigen oder ändern, bei einem einzelnen Objekt auch den Namen.
struct TransferSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State var request: TransferRequest

    private var verb: String { request.move ? "Verschieben" : "Kopieren" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headline).font(.headline)

            Form {
                TextField("Nach:", text: $request.destinationPath)
                if request.isSingle {
                    TextField("Name:", text: $request.newName)
                }
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(verb) { browser.confirmTransfer(request) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var headline: String {
        if request.isSingle {
            return "„\(request.sources[0].lastPathComponent)“ \(verb.lowercased())"
        }
        return "\(request.sources.count) Objekte \(verb.lowercased())"
    }
}
