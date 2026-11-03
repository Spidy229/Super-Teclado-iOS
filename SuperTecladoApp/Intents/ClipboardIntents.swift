import AppIntents
import UIKit

/// Atajo para guardar en el historial lo copiado aunque el teclado esté cerrado. En la app
/// Atajos se combina con «Obtener portapapeles» y se puede lanzar con el toque posterior.
struct SaveToClipboardHistoryIntent: AppIntent {
    static var title: LocalizedStringResource { "Guardar en el portapapeles de Super Teclado" }

    static var description: IntentDescription {
        IntentDescription("Añade un texto al historial del portapapeles de Super Teclado. Pasa el resultado de «Obtener portapapeles» para guardar lo que acabas de copiar.")
    }

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Texto")
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let value = (text ?? UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return .result(dialog: "No hay texto que guardar. Añade antes la acción «Obtener portapapeles».")
        }
        guard ClipboardCapture.captureText(value, changeCount: nil) else {
            return .result(dialog: "No se ha guardado: ya estaba fijado o es un contenido privado que has elegido no guardar.")
        }
        return .result(dialog: "Guardado en el portapapeles de Super Teclado.")
    }
}

struct SuperTecladoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveToClipboardHistoryIntent(),
            phrases: [
                "Guardar el portapapeles en \(.applicationName)",
                "Guardar lo copiado en \(.applicationName)"
            ],
            shortTitle: "Guardar lo copiado",
            systemImageName: "clipboard"
        )
        AppShortcut(
            intent: CopyLatestClipIntent(),
            phrases: ["Copiar lo último de \(.applicationName)"],
            shortTitle: "Copiar lo último",
            systemImageName: "doc.on.doc"
        )
    }
}
