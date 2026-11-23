import AppIntents
import UIKit

/// Copia al portapapeles del sistema el último texto del historial.
struct CopyLatestClipIntent: AppIntent {
    static var title: LocalizedStringResource { "Copiar lo último de Super Teclado" }

    static var description: IntentDescription {
        IntentDescription("Copia el texto más reciente del historial de Super Teclado para pegarlo en cualquier app.")
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let recent = SharedClipboardStore.loadTemporaryInbox().first { !$0.isImage }
        let saved = SharedClipboardStore.load().first { !$0.isImage }
        guard let text = recent?.text ?? saved?.text else {
            return .result(value: "", dialog: "El historial está vacío.")
        }
        UIPasteboard.general.string = text
        return .result(value: text, dialog: "Copiado.")
    }
}

/// Copia un elemento concreto del historial (lo usan los botones del widget).
struct CopyClipIntent: AppIntent {
    static var title: LocalizedStringResource { "Copiar un elemento de Super Teclado" }

    static var isDiscoverable: Bool { false }

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Elemento")
    var clipID: String

    init() {}

    init(clipID: String) {
        self.clipID = clipID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let id = UUID(uuidString: clipID)
        let text = SharedClipboardStore.load().first { $0.id == id }?.text
            ?? SharedClipboardStore.loadTemporaryInbox().first { $0.id == id }?.text
        if let text, !text.isEmpty {
            UIPasteboard.general.string = text
        }
        return .result()
    }
}
