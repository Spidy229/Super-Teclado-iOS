import Combine
import SwiftData
import SwiftUI
import UIKit

private enum LibrarySection: String, CaseIterable, Identifiable {
    case temporary = "Temporales"
    case saved = "Guardados"
    var id: Self { self }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "Todo"
    case text = "Texto"
    case images = "Imágenes"
    case favorites = "Favoritos"
    var id: Self { self }
}

private enum CaptureOrigin { case automatic, manual }

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]

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
    @AppStorage("lastHandledPasteboardChangeCount") private var lastHandledPasteboardChangeCount = -1

    @State private var librarySection: LibrarySection = .temporary
    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var selectedItem: ClipboardItem?
    @State private var showingSettings = false
    @State private var toast: String?
    @State private var folders: [String] = []
    @State private var selectedFolder = ""
    @State private var selectedColor = ""
    @State private var hasCompletedInitialLoad = false
    @State private var isCapturingClipboard = false

    /// `@Query` ya devuelve los elementos ordenados por `updatedAt` descendente: filtramos
    /// primero y separamos fijados arriba en una sola pasada O(n), sin reordenar todo cada vez.
    private var filteredItems: [ClipboardItem] {
        var pinned: [ClipboardItem] = []
        var regular: [ClipboardItem] = []
        for item in items {
            let matchesSection = librarySection == .temporary ? item.isTemporary : item.isPermanent
            guard matchesSection else { continue }
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .text: item.kind != .image
            case .images: item.kind == .image
            case .favorites: item.isFavorite
            }
            guard matchesFilter else { continue }
            if !searchText.isEmpty, !item.searchableText.localizedCaseInsensitiveContains(searchText) { continue }
            if librarySection == .saved {
                if !selectedFolder.isEmpty, item.folderName != selectedFolder { continue }
                if !selectedColor.isEmpty, item.colorTagRawValue != selectedColor { continue }
            }
            if item.isPinned {
                pinned.append(item)
            } else {
                regular.append(item)
            }
        }
        return pinned + regular
    }

    var body: some View {
        NavigationStack {
            Group {
                // Se filtra y ordena una sola vez por dibujado (antes, dos veces).
                let visibleItems = filteredItems
                if visibleItems.isEmpty { emptyState } else { itemList(visibleItems) }
            }
            .navigationTitle("Super Teclado")
            .searchable(text: $searchText, prompt: "Buscar textos, OCR o etiquetas")
            .safeAreaInset(edge: .top, spacing: 0) { filterControls }
            .safeAreaInset(edge: .bottom) { captureButton }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if librarySection == .saved { organizationFilterMenu }
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ajustes")
                }
            }
            .sheet(item: $selectedItem) { item in ItemDetailView(item: item) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .onChange(of: selectedItem?.id) { _, itemID in
                if itemID == nil { reloadFolders() }
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 8, y: 3)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .task {
                await refreshOnForeground()
                hasCompletedInitialLoad = true
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, hasCompletedInitialLoad else { return }
                Task { await refreshOnForeground() }
            }
            .onChange(of: showingSettings) { _, isShowing in
                if !isShowing { reloadFolders(); performMaintenance() }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIPasteboard.changedNotification,
                object: UIPasteboard.general
            )) { _ in
                Task { await captureAutomaticallyIfNeeded() }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                cleanExpiredItems(commit: true)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyDescription)
        }
    }

    private var emptyTitle: String {
        if !searchText.isEmpty || hasOrganizationFilter || filter != .all { return "Sin resultados" }
        return librarySection == .temporary ? "No hay elementos temporales" : "No hay elementos guardados"
    }

    private var emptySymbol: String {
        if emptyTitle == "Sin resultados" { return "line.3.horizontal.decrease.circle" }
        return librarySection == .temporary ? "clock.badge.questionmark" : "archivebox"
    }

    private var emptyDescription: String {
        if emptyTitle == "Sin resultados" { return "Prueba otra búsqueda o limpia los filtros." }
        if librarySection == .temporary {
            return "Copia contenido y vuelve a la app, o pulsa Importar. Nada será permanente hasta que elijas Guardar."
        }
        return "Los elementos que decidas conservar aparecerán aquí y en el teclado."
    }

    private func itemList(_ visibleItems: [ClipboardItem]) -> some View {
        List {
            ForEach(visibleItems) { item in
                Button { selectedItem = item } label: {
                    ClipboardRow(item: item)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if item.isTemporary {
                            Button { promote(item) } label: {
                                Label("Guardar", systemImage: "archivebox.fill")
                            }
                            .tint(.green)
                        } else {
                            Button { item.isFavorite.toggle(); save() } label: {
                                Label(item.isFavorite ? "Quitar favorito" : "Favorito",
                                      systemImage: item.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                            Button { item.isPinned.toggle(); item.updatedAt = .now; save() } label: {
                                Label(item.isPinned ? "Desfijar" : "Fijar",
                                      systemImage: item.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(.cyan)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                        Button { copy(item) } label: {
                            Label("Copiar", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        if item.isTemporary {
                            Button { promote(item) } label: {
                                Label("Guardar permanentemente", systemImage: "archivebox.fill")
                            }
                        }
                        Button { copy(item) } label: { Label("Copiar", systemImage: "doc.on.doc") }
                        if item.isPermanent {
                            Button { item.isPinned.toggle(); save() } label: {
                                Label(item.isPinned ? "Desfijar" : "Fijar", systemImage: "pin")
                            }
                        }
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var filterControls: some View {
        VStack(spacing: 8) {
            Picker("Biblioteca", selection: $librarySection) {
                ForEach(LibrarySection.allCases) { section in Text(section.rawValue).tag(section) }
            }
            .pickerStyle(.segmented)
            if librarySection == .saved {
                Picker("Filtro", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: librarySection) { _, section in
            if section == .temporary { filter = .all; selectedFolder = ""; selectedColor = "" }
        }
    }

    private var hasOrganizationFilter: Bool { !selectedFolder.isEmpty || !selectedColor.isEmpty }

    private var organizationFilterMenu: some View {
        Menu {
            Menu("Carpeta") {
                Button { selectedFolder = "" } label: {
                    Label("Todas las carpetas", systemImage: selectedFolder.isEmpty ? "checkmark" : "folder")
                }
                ForEach(folders, id: \.self) { folder in
                    Button { selectedFolder = folder } label: {
                        Label(folder, systemImage: selectedFolder == folder ? "checkmark" : "folder")
                    }
                }
            }
            Menu("Etiqueta de color") {
                Button { selectedColor = "" } label: {
                    Label("Todos los colores", systemImage: selectedColor.isEmpty ? "checkmark" : "circle")
                }
                ForEach(SharedClipColor.allCases) { color in
                    Button { selectedColor = color.rawValue } label: {
                        Label(color.title, systemImage: selectedColor == color.rawValue ? "checkmark" : "circle.fill")
                    }
                }
            }
            if hasOrganizationFilter {
                Divider()
                Button("Limpiar filtros", role: .destructive) { selectedFolder = ""; selectedColor = "" }
            }
        } label: {
            Image(systemName: hasOrganizationFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtrar por carpeta o color")
    }

    private func reloadFolders() {
        folders = SharedClipboardStore.loadFolders()
        if !selectedFolder.isEmpty && !folders.contains(selectedFolder) { selectedFolder = "" }
    }

    private var captureButton: some View {
        Button { Task { await captureClipboard(origin: .manual) } } label: {
            Label("Importar como temporal", systemImage: "clipboard.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func refreshOnForeground() async {
        reloadFolders()
        KeyboardHistorySync.synchronize(with: modelContext)
        performMaintenance()
        await captureAutomaticallyIfNeeded()
        await recognizeImportedImages()
    }

    private func captureAutomaticallyIfNeeded() async {
        guard automaticCaptureEnabled, scenePhase == .active else { return }
        await captureClipboard(origin: .automatic)
    }

    private func captureClipboard(origin: CaptureOrigin) async {
        guard !isCapturingClipboard else { return }
        let changeCount = UIPasteboard.general.changeCount
        if origin == .automatic && changeCount == lastHandledPasteboardChangeCount { return }
        isCapturingClipboard = true
        defer { isCapturingClipboard = false }
        lastHandledPasteboardChangeCount = changeCount

        switch await ClipboardService.readCurrentAsync() {
        case .empty:
            if origin == .manual { showToast("El portapapeles está vacío") }
        case .privateContent:
            if origin == .manual { showToast("Contenido privado omitido") }
        case .unsupported:
            if origin == .manual { showToast("Este tipo de contenido aún no es compatible") }
        case .content(let draft):
            if let text = draft.text,
               skipOneTimeCodes,
               ClipboardService.isLikelyOneTimeCode(text) {
                if origin == .manual { showToast("Código temporal omitido por privacidad") }
                return
            }

            var isSensitive = false
            if let text = draft.text, ClipboardClassifier.isSensitive(text) {
                switch SharedClipboardStore.sensitiveMode {
                case .skip:
                    if origin == .manual { showToast("Contenido privado omitido") }
                    return
                case .mask:
                    isSensitive = true
                case .normal:
                    break
                }
            }

            if let existing = existingItem(withContentHash: draft.contentHash) {
                existing.updatedAt = .now
                if existing.isTemporary {
                    existing.expiresAt = ClipboardRetentionPolicy.expirationDate(hours: temporaryRetentionHours)
                    if origin == .manual { showToast("Temporal actualizado") }
                } else if origin == .manual {
                    showToast("Ya está guardado permanentemente")
                }
                save()
                return
            }

            let item = ClipboardItem(
                text: draft.text,
                imageData: draft.imageData,
                kind: draft.kind,
                contentHash: draft.contentHash,
                isTemporary: true,
                expiresAt: isSensitive
                    ? Date.now.addingTimeInterval(ClipboardClassifier.sensitiveLifetime)
                    : ClipboardRetentionPolicy.expirationDate(hours: temporaryRetentionHours),
                isSensitive: isSensitive
            )
            modelContext.insert(item)
            _ = trimHistoryIfNeeded(commit: false)
            save()
            librarySection = .temporary
            showToast(origin == .automatic ? "Añadido a Temporales" : "Importado temporalmente")

            if let imageData = draft.imageData {
                Task {
                    item.recognizedText = await OCRService.recognizeText(in: imageData) ?? ""
                    save()
                }
            }
        }
    }

    private func promote(_ item: ClipboardItem) {
        item.promoteToPermanent()
        _ = trimHistoryIfNeeded(commit: false)
        save()
        showToast("Guardado permanentemente")
    }

    private func existingItem(withContentHash contentHash: String) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == contentHash }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func copy(_ item: ClipboardItem) {
        if ClipboardService.copy(item, localOnly: localClipboardOnly) {
            item.updatedAt = .now
            save()
            lastHandledPasteboardChangeCount = UIPasteboard.general.changeCount
            showToast("Copiado")
        }
    }

    private func delete(_ item: ClipboardItem) {
        KeyboardHistorySync.delete(item, from: modelContext)
        save()
        showToast("Eliminado")
    }

    /// Extrae el texto de las capturas copiadas desde el teclado para poder buscarlas.
    private func recognizeImportedImages() async {
        // Comprueba `kind` y `recognizedText` antes de tocar `imageData` para no leer discos innecesarios.
        let pending = items.filter { $0.kind == .image && $0.recognizedText == nil }
        guard !pending.isEmpty else { return }
        var recognizedAny = false
        for item in pending {
            guard let data = item.imageData else { continue }
            item.recognizedText = await OCRService.recognizeText(in: data) ?? ""
            recognizedAny = true
        }
        if recognizedAny { save() }
    }

    private func performMaintenance() {
        let expiredChanged = cleanExpiredItems(commit: false)
        let trimmedChanged = trimHistoryIfNeeded(commit: false)
        if expiredChanged || trimmedChanged { save() }
    }

    @discardableResult
    private func cleanExpiredItems(commit: Bool = true) -> Bool {
        let now = Date.now
        var changed = false
        for item in items where ClipboardRetentionPolicy.isExpired(
            isTemporary: item.isTemporary,
            expiresAt: item.expiresAt,
            at: now
        ) {
            KeyboardHistorySync.delete(item, from: modelContext)
            changed = true
        }
        if autoDeleteDays > 0,
           let threshold = Calendar.current.date(byAdding: .day, value: -autoDeleteDays, to: now) {
            for item in items where item.isPermanent && item.updatedAt < threshold && !item.isFavorite && !item.isPinned {
                KeyboardHistorySync.delete(item, from: modelContext)
                changed = true
            }
        }
        if changed && commit { save() }
        return changed
    }

    @discardableResult
    private func trimHistoryIfNeeded(commit: Bool = true) -> Bool {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .forward)]
        )
        guard let storedItems = try? modelContext.fetch(descriptor) else { return false }

        let temporaryItems = storedItems.filter(\.isTemporary)
        let temporaryOverflow = max(0, temporaryItems.count - max(1, maximumTemporaryItems))
        for item in temporaryItems.prefix(temporaryOverflow) { KeyboardHistorySync.delete(item, from: modelContext) }

        let permanentItems = storedItems.filter(\.isPermanent)
        let permanentOverflow = max(0, permanentItems.count - max(1, maximumItems))
        let removable = permanentItems.filter { !$0.isPinned && !$0.isFavorite }
        for item in removable.prefix(permanentOverflow) { KeyboardHistorySync.delete(item, from: modelContext) }

        let changed = temporaryOverflow > 0 || permanentOverflow > 0
        if changed && commit { save() }
        return changed
    }

    private func save() {
        do {
            try KeyboardHistorySync.commit(modelContext)
        } catch {
            showToast("No se pudieron guardar los cambios")
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut) {
                if toast == message { toast = nil }
            }
        }
    }
}
