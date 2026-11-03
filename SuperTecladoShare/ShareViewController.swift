import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private final class ShareModel: ObservableObject {
    enum State {
        case saving
        case saved(Int)
        case nothing
    }

    @Published var state: State = .saving
    @Published var pinned = false
}

/// «Compartir › Super Teclado»: guarda textos, enlaces e imágenes en el historial del
/// portapapeles aunque el teclado esté cerrado.
final class ShareViewController: UIViewController {
    private let model = ShareModel()
    private var startDate = Date()
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let host = UIHostingController(rootView: ShareStatusView(
            model: model,
            onPin: { [weak self] in self?.pinSavedItems() },
            onDone: { [weak self] in self?.finish() }
        ))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        Task { await saveSharedItems() }
    }

    private func saveSharedItems() async {
        startDate = Date()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var count = 0
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if await save(provider) { count += 1 }
        }
        model.state = count > 0 ? .saved(count) : .nothing

        try? await Task.sleep(for: .seconds(count > 0 ? 3 : 1.6))
        if !model.pinned { finish() }
    }

    private func save(_ provider: NSItemProvider) async -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            guard let data = await loadData(from: provider, type: .image) else { return false }
            return ClipboardCapture.captureImage(data, changeCount: nil)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(from: provider), !url.isFileURL {
            return ClipboardCapture.captureText(url.absoluteString, changeCount: nil)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadText(from: provider) {
            return ClipboardCapture.captureText(text, changeCount: nil)
        }
        return false
    }

    private func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    /// Pasa a Fijados lo que se acaba de guardar.
    private func pinSavedItems() {
        let recent = SharedClipboardStore.loadTemporaryInbox().filter { $0.capturedAt >= startDate }
        recent.forEach { SharedClipboardStore.promoteTemporary(id: $0.id) }
        model.pinned = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

private struct ShareStatusView: View {
    @ObservedObject var model: ShareModel
    let onPin: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onDone)

            VStack(spacing: 14) {
                icon
                    .font(.system(size: 40))
                    .foregroundStyle(.cyan)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if case .saved = model.state, !model.pinned {
                    HStack(spacing: 10) {
                        Button(action: onPin) {
                            Label("Fijar", systemImage: "pin.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button("Listo", action: onDone)
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                    }
                    .tint(.cyan)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(30)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .saving: ProgressView().controlSize(.large)
        case .saved: Image(systemName: model.pinned ? "pin.circle.fill" : "checkmark.circle.fill")
        case .nothing: Image(systemName: "tray")
        }
    }

    private var title: String {
        switch model.state {
        case .saving:
            return "Guardando…"
        case .saved(let count):
            if model.pinned { return "Fijado en Super Teclado" }
            return count == 1 ? "Guardado en Super Teclado" : "\(count) elementos guardados"
        case .nothing:
            return "No había nada nuevo que guardar"
        }
    }

    private var detail: String {
        switch model.state {
        case .saving: ""
        case .saved: "Lo tienes en el portapapeles del teclado, en Recientes."
        case .nothing: "Quizá ya estaba guardado o es contenido privado."
        }
    }
}
