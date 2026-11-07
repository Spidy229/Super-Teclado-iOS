import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ClipboardItem]

    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @AppStorage(
        "skipOneTimeCodes",
        store: SharedClipboardStore.sharedDefaults
    ) private var skipOneTimeCodes = true
    @AppStorage("localClipboardOnly") private var localClipboardOnly = true
    @AppStorage("maximumItems") private var maximumItems = 250
    @AppStorage("autoDeleteDays") private var autoDeleteDays = 30
    @AppStorage(
        "automaticCaptureEnabled",
        store: SharedClipboardStore.sharedDefaults
    ) private var automaticCaptureEnabled = true
    @AppStorage(
        "temporaryRetentionHours",
        store: SharedClipboardStore.sharedDefaults
    ) private var temporaryRetentionHours = ClipboardRetentionPolicy.defaultTemporaryHours
    @AppStorage(
        "maximumTemporaryItems",
        store: SharedClipboardStore.sharedDefaults
    ) private var maximumTemporaryItems = ClipboardRetentionPolicy.defaultMaximumTemporaryItems

    @AppStorage(
        SharedClipboardStore.sensitiveModeKey,
        store: SharedClipboardStore.sharedDefaults
    ) private var sensitiveMode: SensitiveClipMode = .mask

    @State private var showDeleteConfirmation = false
    @State private var showOnboarding = false
    @State private var showClearTemporaryConfirmation = false
    @State private var folders: [String] = []
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Proteger con Face ID", isOn: $requireBiometrics)
                    Toggle("No guardar códigos de un solo uso", isOn: $skipOneTimeCodes)
                    Toggle("Copiar solo en este dispositivo", isOn: $localClipboardOnly)
                } header: {
                    Text("Privacidad")
                } footer: {
                    Text("El modo local evita que lo copiado se envíe mediante Portapapeles universal.")
                }

                Section {
                    Toggle("Captura automática", isOn: $automaticCaptureEnabled)

                    Picker("Conservar temporales", selection: $temporaryRetentionHours) {
                        Text("1 hora").tag(1)
                        Text("6 horas").tag(6)
                        Text("24 horas").tag(24)
                        Text("3 días").tag(72)
                        Text("7 días").tag(168)
                        Text("30 días").tag(720)
                        Text("Sin caducidad").tag(-1)
                    }

                    Picker("Límite temporal", selection: $maximumTemporaryItems) {
                        Text("10 elementos").tag(10)
                        Text("25 elementos").tag(25)
                        Text("50 elementos").tag(50)
                        Text("100 elementos").tag(100)
                        Text("250 elementos").tag(250)
                        Text("500 elementos").tag(500)
                    }

                    Picker("Contenido privado", selection: $sensitiveMode) {
                        ForEach(SensitiveClipMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }

                    NavigationLink {
                        ClipboardCaptureGuideView()
                    } label: {
                        Label("Guardar con el teclado cerrado", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Bandeja temporal")
                } footer: {
                    Text("Se considera privado lo que parece una tarjeta, un IBAN, una contraseña o un código. Lo que los gestores de contraseñas marcan como oculto nunca se guarda.")
                }

                Section {
                    Picker("Límite", selection: $maximumItems) {
                        Text("50 elementos").tag(50)
                        Text("100 elementos").tag(100)
                        Text("250 elementos").tag(250)
                        Text("500 elementos").tag(500)
                    }

                    Picker("Borrado automático", selection: $autoDeleteDays) {
                        Text("Nunca").tag(0)
                        Text("Después de 1 día").tag(1)
                        Text("Después de 7 días").tag(7)
                        Text("Después de 30 días").tag(30)
                        Text("Después de 90 días").tag(90)
                    }
                } header: {
                    Text("Historial")
                } footer: {
                    Text("Los favoritos y los elementos fijados nunca se eliminan automáticamente.")
                }

                Section {
                    HStack {
                        TextField("Nombre de la carpeta", text: $newFolderName)
                        Button(action: addFolder) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Crear carpeta")
                    }

                    if folders.isEmpty {
                        Text("Todavía no has creado carpetas.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(folders, id: \.self) { folder in
                            Label(folder, systemImage: "folder")
                        }
                        .onDelete(perform: deleteFolders)
                    }
                } header: {
                    Text("Carpetas")
                } footer: {
                    Text("Desliza una carpeta para eliminarla. Los elementos se conservarán sin carpeta.")
                }

                Section("Datos locales") {
                    LabeledContent("Temporales", value: "\(items.filter(\.isTemporary).count)")
                    LabeledContent("Guardados", value: "\(items.filter(\.isPermanent).count)")
                    Button("Vaciar bandeja temporal", role: .destructive) {
                        showClearTemporaryConfirmation = true
                    }
                    Button("Borrar guardados no protegidos", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }

                Section {
                    KeyboardStatusView()
                    NavigationLink {
                        KeyboardSettingsView()
                    } label: {
                        Label("Ajustes del teclado", systemImage: "keyboard")
                    }
                    NavigationLink {
                        KeyboardThemesView()
                    } label: {
                        Label("Temas del teclado", systemImage: "paintpalette")
                    }
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Ver la guía de bienvenida", systemImage: "sparkles")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Abrir ajustes para activar el teclado", systemImage: "gear")
                    }
                } header: {
                    Text("Teclado")
                } footer: {
                    Text("Añade Super Teclado en Teclados y activa Acceso total. Lo que copies aparecerá en Recientes del portapapeles del teclado; mantén pulsado un elemento para fijarlo.")
                }

                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Copia de seguridad", systemImage: "externaldrive.badge.icloud")
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnóstico del teclado", systemImage: "stethoscope")
                    }
                } header: {
                    Text("Mantenimiento")
                } footer: {
                    Text("Haz una copia antes de reinstalar la app con otro certificado: al cambiarlo se pueden perder los datos.")
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: appVersion)
                    Text("Los datos se guardan únicamente en el dispositivo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Diccionarios basados en FrequencyWords de Hermit Dave (OpenSubtitles, CC BY-SA 4.0). Predicción con frases de Tatoeba (CC BY 2.0 FR). Nombres de emojis de Unicode CLDR (© Unicode, Inc., licencia Unicode V3).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .confirmationDialog(
                "¿Borrar el historial?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar textos e imágenes", role: .destructive) {
                    deleteUnprotectedItems()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se conservarán los favoritos y los elementos fijados.")
            }
            .confirmationDialog(
                "¿Vaciar los temporales?",
                isPresented: $showClearTemporaryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar todos los temporales", role: .destructive) {
                    deleteTemporaryItems()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Los elementos guardados permanentemente no se modificarán.")
            }
            .onAppear {
                folders = SharedClipboardStore.loadFolders()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.6"
    }

    private func addFolder() {
        guard SharedClipboardStore.addFolder(newFolderName) != nil else { return }
        folders = SharedClipboardStore.loadFolders()
        newFolderName = ""
    }

    private func deleteFolders(at offsets: IndexSet) {
        let names = offsets.map { folders[$0] }
        for name in names {
            for item in items where item.folderName == name {
                item.folderName = nil
            }
            SharedClipboardStore.removeFolder(name)
        }
        try? KeyboardHistorySync.commit(modelContext)
        folders = SharedClipboardStore.loadFolders()
    }

    private func deleteUnprotectedItems() {
        for item in items where item.isPermanent && !item.isFavorite && !item.isPinned {
            KeyboardHistorySync.delete(item, from: modelContext)
        }
        try? KeyboardHistorySync.commit(modelContext)
    }

    private func deleteTemporaryItems() {
        for item in items where item.isTemporary {
            KeyboardHistorySync.delete(item, from: modelContext)
        }
        try? KeyboardHistorySync.commit(modelContext)
    }
}
