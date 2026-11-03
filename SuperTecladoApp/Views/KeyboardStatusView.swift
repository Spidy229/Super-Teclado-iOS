import SwiftUI

/// Indica si el teclado ya se ha usado con acceso total. El teclado solo puede escribir en el
/// App Group con acceso total, así que si nunca lo ha hecho falta activarlo.
struct KeyboardStatusView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastActive: Date?

    var body: some View {
        Group {
            if let lastActive {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Teclado activado con acceso total")
                            .font(.subheadline.weight(.semibold))
                        Text("Usado por última vez \(lastActive.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activa el teclado")
                            .font(.subheadline.weight(.semibold))
                        Text("Añade Super Teclado en Ajustes › General › Teclado y activa «Permitir acceso total». Después ábrelo en cualquier app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func reload() {
        let value = SharedClipboardStore.sharedDefaults?.double(forKey: KeyboardPreferenceKey.lastActive) ?? 0
        lastActive = value > 0 ? Date(timeIntervalSince1970: value) : nil
    }
}
