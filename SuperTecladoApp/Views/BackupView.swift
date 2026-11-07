import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Exportar e importar la copia de seguridad.
struct BackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ClipboardItem]

    @State private var includeImages = true
    @State private var exportURL: URL?
    @State private var isWorking = false
    @State private var showingImporter = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                Toggle("Incluir imágenes", isOn: $includeImages)
                Button(action: createBackup) {
                    Label("Crear copia de seguridad", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(isWorking)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Guardar o compartir la copia", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Exportar")
            } footer: {
                Text("Incluye \(items.count) elementos del historial, carpetas, palabras aprendidas, atajos y ajustes del teclado. Guárdala en Archivos o en iCloud Drive antes de reinstalar la app con otro certificado.")
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Restaurar desde un archivo", systemImage: "arrow.down.doc")
                }
                .disabled(isWorking)
            } header: {
                Text("Importar")
            } footer: {
                Text("Se añade a lo que ya tienes: los elementos repetidos no se duplican.")
            }

            if isWorking {
                Section { ProgressView() }
            }
            if let message {
                Section {
                    Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? .red : .green)
                }
            }
        }
        .navigationTitle("Copia de seguridad")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): restore(from: url)
            case .failure: show("No se pudo abrir el archivo.", error: true)
            }
        }
    }

    private func createBackup() {
        isWorking = true
        message = nil
        let backup = BackupService.makeBackup(from: modelContext, includeImages: includeImages)
        let date = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SuperTeclado-copia-\(date).json")
        Task {
            let written = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let data = try? BackupService.encodeDetached(backup) else { return false }
                return (try? data.write(to: url, options: .atomic)) != nil
            }.value
            isWorking = false
            if written {
                exportURL = url
                show("Copia creada. Pulsa «Guardar o compartir la copia».", error: false)
            } else {
                show("No se pudo crear la copia.", error: true)
            }
        }
    }

    private func restore(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let backup = try BackupService.decode(data)
            let summary = try BackupService.restore(backup, into: modelContext)
            show(
                "Restaurados \(summary.items) elementos (\(summary.skipped) ya estaban), \(summary.words) palabras y \(summary.shortcuts) atajos.",
                error: false
            )
        } catch {
            show("El archivo no es una copia válida de Super Teclado.", error: true)
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
