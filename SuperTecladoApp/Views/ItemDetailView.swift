import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: ClipboardItem
    @AppStorage("localClipboardOnly") private var localClipboardOnly = true
    @State private var copied = false
    @State private var folders: [String] = []
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Estado") {
                    if item.isTemporary {
                        Label("Temporal", systemImage: "clock")
                            .foregroundStyle(.orange)
                        if let expiresAt = item.expiresAt {
                            LabeledContent("Caduca") {
                                Text(expiresAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        Button(action: promote) {
                            Label("Guardar permanentemente", systemImage: "archivebox.fill")
                        }
                    } else {
                        Label("Guardado permanentemente", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("Contenido") {
                    if let data = item.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if let text = item.text {
                        Text(text)
                            .textSelection(.enabled)
                    }

                    if let recognizedText = item.recognizedText {
                        LabeledContent("Texto detectado") {
                            Text(recognizedText)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }

                if item.isPermanent {
                    Section("Organización") {
                        Toggle("Favorito", isOn: $item.isFavorite)
                        Toggle("Fijado arriba", isOn: $item.isPinned)

                        Picker("Carpeta", selection: folderBinding) {
                            Text("Sin carpeta").tag("")
                            ForEach(folders, id: \.self) { folder in
                                Label(folder, systemImage: "folder")
                                    .tag(folder)
                            }
                        }

                        HStack {
                            TextField("Nueva carpeta", text: $newFolderName)
                            Button(action: createFolder) {
                                Image(systemName: "folder.badge.plus")
                            }
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Crear carpeta")
                        }

                        Picker("Etiqueta de color", selection: colorBinding) {
                            Text("Sin color").tag("")
                            ForEach(SharedClipColor.allCases) { color in
                                Label(color.title, systemImage: "circle.fill")
                                    .foregroundStyle(color.color)
                                    .tag(color.rawValue)
                            }
                        }

                        TextField("Etiquetas separadas por comas", text: $item.tagsText)
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("Información") {
                    LabeledContent("Tipo", value: item.kind.title)
                    LabeledContent("Guardado") {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .navigationTitle("Detalle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copied = ClipboardService.copy(item, localOnly: localClipboardOnly)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel(copied ? "Copiado" : "Copiar")
                }
            }
            .onDisappear {
                item.updatedAt = .now
                try? KeyboardHistorySync.commit(modelContext)
            }
            .onAppear {
                folders = SharedClipboardStore.loadFolders()
            }
        }
    }

    private var folderBinding: Binding<String> {
        Binding(
            get: { item.folderName ?? "" },
            set: { item.folderName = $0.isEmpty ? nil : $0 }
        )
    }

    private var colorBinding: Binding<String> {
        Binding(
            get: { item.colorTagRawValue ?? "" },
            set: { item.colorTagRawValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func createFolder() {
        guard let folder = SharedClipboardStore.addFolder(newFolderName) else { return }
        folders = SharedClipboardStore.loadFolders()
        item.folderName = folder
        newFolderName = ""
    }

    private func promote() {
        item.promoteToPermanent()
        try? KeyboardHistorySync.commit(modelContext)
    }
}
