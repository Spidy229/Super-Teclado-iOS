import SwiftUI
import UIKit

/// Solo aparece cuando la firma no incluye el App Group: los ajustes de la app no llegan solos
/// al teclado, así que se envían por el portapapeles y el teclado los aplica al abrirse.
struct KeyboardSettingsTransferSection: View {
    @State private var sentAt: Date?
    @State private var failed = false

    var body: some View {
        if !SharedClipboardStore.isAppGroupAvailable {
            Section {
                Button(action: send) {
                    Label("Enviar ajustes al teclado", systemImage: "keyboard.badge.ellipsis")
                }
                if sentAt != nil {
                    Text("Enviados. Abre el teclado en cualquier campo de texto (por ejemplo, en «Probar» de Ajustes del teclado) y se aplicarán al momento.")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else if failed {
                    Text("Aún no has cambiado ningún ajuste en la app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pasar los ajustes al teclado")
            } footer: {
                Text("Con esta firma la app y el teclado no comparten datos, así que lo que cambies aquí no llega solo al teclado. Al enviarlos se sustituye lo que tengas copiado durante unos minutos; el teclado necesita el acceso total. También puedes cambiarlos desde el engranaje ⚙︎ de la barra del teclado.")
            }
        }
    }

    private func send() {
        guard let data = KeyboardSettingsTransfer.payload(from: SharedClipboardStore.sharedDefaults) else {
            failed = true
            sentAt = nil
            return
        }
        // Caduca a los 10 minutos y no pasa a otros dispositivos por Handoff.
        UIPasteboard.general.setItems(
            [[KeyboardSettingsTransfer.pasteboardType: data]],
            options: [.expirationDate: Date().addingTimeInterval(600), .localOnly: true]
        )
        failed = false
        sentAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
