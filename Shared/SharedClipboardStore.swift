import Foundation
import SwiftUI

enum SharedClipColor: String, Codable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: Self { self }

    var title: String {
        switch self {
        case .red: "Rojo"
        case .orange: "Naranja"
        case .yellow: "Amarillo"
        case .green: "Verde"
        case .blue: "Azul"
        case .purple: "Morado"
        case .gray: "Gris"
        }
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }
}

struct SharedClipboardClip: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var kindRawValue: String
    var isFavorite: Bool
    var isPinned: Bool
    var folderName: String? = nil
    var colorTagRawValue: String? = nil
    var imageFileName: String? = nil
    /// Tarjetas, IBAN, contraseñas o códigos: se muestran ocultos.
    var isSensitive: Bool? = nil

    var kindSymbol: String { SharedClipboardStore.symbol(forKind: kindRawValue) }
    var isImage: Bool { imageFileName != nil }
}

struct SharedTemporaryClip: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var capturedAt: Date
    var kindRawValue: String
    var expiresAt: Date?
    var pasteboardChangeCount: Int? = nil
    var imageFileName: String? = nil
    var imageHash: String? = nil
    var isSensitive: Bool? = nil

    var isImage: Bool { imageFileName != nil }
}

enum SharedClipboardStore {
    static let appGroupID = "group.com.spidy229.superteclado"
    static let automaticCaptureKey = "automaticCaptureEnabled"
    private static let fileName = "super-teclado-history.json"
    private static let temporaryInboxFileName = "super-teclado-temporary-inbox.json"
    private static let imagesDirectoryName = "super-teclado-images"
    private static let foldersKey = "super-teclado-folders"
    private static let savedFallbackKey = "super-teclado-saved-fallback"
    private static let temporaryFallbackKey = "super-teclado-temporary-fallback"
    private static let deletedIDsKey = "super-teclado-deleted-ids"
    static let sensitiveModeKey = "clipboardSensitiveMode"
    /// Imágenes que se conservan como máximo en Recientes, aparte del límite general.
    static let maximumTemporaryImages = 100

    /// Una sola instancia para todo el proceso: crearla en cada lectura (y en cada redibujado de
    /// los ajustes de la app, una por ajuste) costaba tiempo del hilo principal.
    nonisolated(unsafe) static let sharedDefaults: UserDefaults? = UserDefaults(suiteName: appGroupID)

    /// `false` si la firma de la app no incluye el App Group: entonces la app y el teclado no
    /// comparten ajustes ni portapapeles (cada uno guarda los suyos).
    static var isAppGroupAvailable: Bool { containerURL() != nil }

    static var automaticCaptureEnabled: Bool {
        get {
            guard sharedDefaults?.object(forKey: automaticCaptureKey) != nil else { return true }
            return sharedDefaults?.bool(forKey: automaticCaptureKey) ?? true
        }
        set { sharedDefaults?.set(newValue, forKey: automaticCaptureKey) }
    }

    static var skipOneTimeCodes: Bool {
        guard sharedDefaults?.object(forKey: "skipOneTimeCodes") != nil else { return true }
        return sharedDefaults?.bool(forKey: "skipOneTimeCodes") ?? true
    }

    /// Horas que se conservan los recientes; un valor negativo significa «sin caducidad».
    static var temporaryRetentionHours: Int {
        let value = sharedDefaults?.integer(forKey: "temporaryRetentionHours") ?? 0
        return value == 0 ? 24 : value
    }

    static var sensitiveMode: SensitiveClipMode {
        sharedDefaults?.string(forKey: sensitiveModeKey).flatMap(SensitiveClipMode.init(rawValue:)) ?? .mask
    }

    static var maximumTemporaryItems: Int {
        let value = sharedDefaults?.integer(forKey: "maximumTemporaryItems") ?? 0
        return value > 0 ? value : 50
    }

    /// Ubicaciones explícitas para pruebas aisladas; sin App Group, las imágenes se guardan
    /// en el contenedor privado del proceso, igual que el respaldo JSON de UserDefaults.
    struct Storage {
        let directoryURL: URL?
        let localDirectoryURL: URL
        let defaults: UserDefaults
        let settingsDefaults: UserDefaults?

        static var live: Storage {
            Storage(directoryURL: cachedContainerURL, localDirectoryURL: cachedLocalDirectoryURL,
                    defaults: .standard, settingsDefaults: sharedDefaults)
        }
    }

    // MARK: Guardados

    static func load(storage: Storage = .live) -> [SharedClipboardClip] {
        sort(readList(at: historyURL(storage: storage), fallbackKey: savedFallbackKey, storage: storage))
    }

    @discardableResult
    static func save(_ clips: [SharedClipboardClip], storage: Storage = .live) -> Bool {
        let sorted = sort(clips)
        if let url = historyURL(storage: storage) { return encodeFile(sorted, at: url) }
        return encodeDefaults(sorted, forKey: savedFallbackKey, storage: storage)
    }

    /// No convertir errores de lectura en un historial vacío que sobrescriba los datos.
    static func canRead(storage: Storage = .live) -> Bool {
        canReadList(SharedClipboardClip.self, at: historyURL(storage: storage),
                    fallbackKey: savedFallbackKey, storage: storage)
            && canReadList(SharedTemporaryClip.self, at: temporaryInboxURL(storage: storage),
                           fallbackKey: temporaryFallbackKey, storage: storage)
    }

    static func addCopiedText(_ text: String, maximumItems: Int = 250) {
        let value = text
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var clips = load()
        if let index = clips.firstIndex(where: { !$0.isImage && $0.text == value }) {
            clips[index].updatedAt = .now
        } else {
            clips.append(
                SharedClipboardClip(
                    id: UUID(),
                    text: value,
                    createdAt: .now,
                    updatedAt: .now,
                    kindRawValue: detectKind(value),
                    isFavorite: false,
                    isPinned: false
                )
            )
        }
        save(Array(sort(clips).prefix(maximumItems)))
    }

    static func toggleFavorite(id: UUID) {
        var clips = load()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].isFavorite.toggle()
        clips[index].updatedAt = .now
        save(clips)
    }

    static func markUsed(id: UUID) {
        var clips = load()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].updatedAt = .now
        save(clips)
    }

    /// Elimina elementos guardados y deja constancia para que la app no los restaure.
    /// Con `removeImages: false` las imágenes se conservan para poder deshacer el borrado.
    @discardableResult
    static func deleteSaved(ids: Set<UUID>, removeImages: Bool = true) -> [SharedClipboardClip] {
        guard !ids.isEmpty else { return [] }
        var clips = load()
        let removed = clips.filter { ids.contains($0.id) }
        clips.removeAll { ids.contains($0.id) }
        save(clips)
        recordDeletion(of: ids)
        if removeImages { removed.compactMap(\.imageFileName).forEach { removeImage(fileName: $0) } }
        return removed
    }

    /// Deshace un borrado reciente.
    static func restore(saved: [SharedClipboardClip], temporary: [SharedTemporaryClip]) {
        let ids = Set(saved.map(\.id) + temporary.map(\.id))
        guard !ids.isEmpty else { return }
        forgetDeletion(of: ids)
        if !saved.isEmpty {
            var clips = load()
            let existing = Set(clips.map(\.id))
            clips += saved.filter { !existing.contains($0.id) }
            save(clips)
        }
        if !temporary.isEmpty {
            var clips = loadTemporaryInbox()
            let existing = Set(clips.map(\.id))
            clips += temporary.filter { !existing.contains($0.id) }
            saveTemporaryInbox(clips.sorted { $0.capturedAt > $1.capturedAt })
        }
    }

    /// Cambia la carpeta de un elemento guardado.
    static func setFolder(_ folder: String?, forSavedID id: UUID) {
        var clips = load()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].folderName = folder
        clips[index].updatedAt = .now
        save(clips)
    }

    /// Devuelve un elemento guardado a Recientes, como «Desfijar» en Gboard.
    @discardableResult
    static func demoteSaved(id: UUID, storage: Storage = .live) -> Bool {
        var clips = load(storage: storage)
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        let clip = clips.remove(at: index)
        save(clips, storage: storage)
        recordDeletion(of: [id], storage: storage)

        var temporary = loadTemporaryInbox(storage: storage)
        temporary.removeAll { existing in
            clip.isImage ? existing.imageFileName == clip.imageFileName : existing.text == clip.text
        }
        temporary.append(
            SharedTemporaryClip(
                id: UUID(),
                text: clip.text,
                capturedAt: .now,
                kindRawValue: clip.kindRawValue,
                expiresAt: clip.isSensitive == true
                    ? .now.addingTimeInterval(ClipboardClassifier.sensitiveLifetime)
                    : temporaryExpiration(storage: storage),
                imageFileName: clip.imageFileName,
                isSensitive: clip.isSensitive
            )
        )
        saveTemporaryInbox(temporary, storage: storage)
        return true
    }

    // MARK: Recientes (temporales)

    /// Añade un texto a Recientes. `pasteboardChangeCount` evita guardar dos veces la misma
    /// copia; es `nil` cuando el texto llega desde «Compartir» o desde Atajos.
    @discardableResult
    static func captureTemporaryText(
        _ text: String,
        pasteboardChangeCount: Int?,
        maximumItems: Int? = nil,
        isSensitive: Bool = false,
        storage: Storage = .live
    ) -> Bool {
        let value = text
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        guard canRead(storage: storage) else { return false }
        var clips = loadTemporaryInbox(storage: storage)
        if let pasteboardChangeCount,
           clips.contains(where: { $0.pasteboardChangeCount == pasteboardChangeCount }) {
            return false
        }
        let expiration = isSensitive
            ? Date.now.addingTimeInterval(ClipboardClassifier.sensitiveLifetime)
            : temporaryExpiration(storage: storage)
        if load(storage: storage).contains(where: { !$0.isImage && $0.text == value }) {
            // Ya está fijado: no se duplica en Recientes.
            return false
        }

        if let index = clips.firstIndex(where: { !$0.isImage && $0.text == value }) {
            // Igual que Gboard: volver a copiar algo lo sube al principio.
            clips[index].capturedAt = .now
            clips[index].expiresAt = expiration
            clips[index].pasteboardChangeCount = pasteboardChangeCount
            clips[index].isSensitive = isSensitive ? true : nil
        } else {
            clips.append(
                SharedTemporaryClip(
                    id: UUID(),
                    text: value,
                    capturedAt: .now,
                    kindRawValue: detectKind(value),
                    expiresAt: expiration,
                    pasteboardChangeCount: pasteboardChangeCount,
                    isSensitive: isSensitive ? true : nil
                )
            )
        }

        return saveTrimmedTemporaryInbox(clips, maximumItems: maximumItems ?? maximumTemporaryItems, storage: storage)
    }

    @discardableResult
    static func captureTemporaryImage(
        _ data: Data,
        hash: String,
        pasteboardChangeCount: Int?,
        maximumItems: Int? = nil,
        storage: Storage = .live
    ) -> Bool {
        guard canRead(storage: storage) else { return false }
        var clips = loadTemporaryInbox(storage: storage)
        if let pasteboardChangeCount,
           clips.contains(where: { $0.pasteboardChangeCount == pasteboardChangeCount }) {
            return false
        }

        if let index = clips.firstIndex(where: { $0.imageHash == hash }) {
            clips[index].capturedAt = .now
            clips[index].expiresAt = temporaryExpiration(storage: storage)
            clips[index].pasteboardChangeCount = pasteboardChangeCount
        } else {
            let id = UUID()
            let imageFileName = "\(id.uuidString).jpg"
            guard writeImage(data, fileName: imageFileName, storage: storage) else { return false }
            clips.append(
                SharedTemporaryClip(
                    id: id,
                    text: "",
                    capturedAt: .now,
                    kindRawValue: "image",
                    expiresAt: temporaryExpiration(storage: storage),
                    pasteboardChangeCount: pasteboardChangeCount,
                    imageFileName: imageFileName,
                    imageHash: hash
                )
            )
        }

        return saveTrimmedTemporaryInbox(clips, maximumItems: maximumItems ?? maximumTemporaryItems, storage: storage)
    }

    static func loadTemporaryInbox(storage: Storage = .live) -> [SharedTemporaryClip] {
        let clips: [SharedTemporaryClip] = readList(at: temporaryInboxURL(storage: storage), fallbackKey: temporaryFallbackKey, storage: storage)
        return clips
            .filter { $0.expiresAt.map { $0 > .now } ?? true }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    static func clearTemporaryInbox(storage: Storage = .live) {
        saveTemporaryInbox([], storage: storage)
    }

    @discardableResult
    static func replaceTemporaryInbox(_ clips: [SharedTemporaryClip], storage: Storage = .live) -> Bool {
        saveTemporaryInbox(clips.sorted { $0.capturedAt > $1.capturedAt }, storage: storage)
    }

    static func markTemporaryUsed(id: UUID) {
        var clips = loadTemporaryInbox()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].capturedAt = .now
        saveTemporaryInbox(clips)
    }

    @discardableResult
    static func deleteTemporary(ids: Set<UUID>, removeImages: Bool = true) -> [SharedTemporaryClip] {
        guard !ids.isEmpty else { return [] }
        var clips = loadTemporaryInbox()
        let removed = clips.filter { ids.contains($0.id) }
        clips.removeAll { ids.contains($0.id) }
        saveTemporaryInbox(clips)
        recordDeletion(of: ids)
        if removeImages { removed.compactMap(\.imageFileName).forEach { removeImage(fileName: $0) } }
        return removed
    }

    @discardableResult
    static func promoteTemporary(id: UUID, storage: Storage = .live) -> Bool {
        var temporary = loadTemporaryInbox(storage: storage)
        guard let index = temporary.firstIndex(where: { $0.id == id }) else { return false }
        let clip = temporary.remove(at: index)

        var saved = load(storage: storage)
        if !clip.isImage, let existingIndex = saved.firstIndex(where: { !$0.isImage && $0.text == clip.text }) {
            saved[existingIndex].updatedAt = .now
            saved[existingIndex].isPinned = true
            saved[existingIndex].isSensitive = clip.isSensitive
        } else {
            saved.append(
                SharedClipboardClip(
                    id: clip.id,
                    text: clip.text,
                    createdAt: clip.capturedAt,
                    updatedAt: .now,
                    kindRawValue: clip.kindRawValue,
                    isFavorite: false,
                    isPinned: true,
                    imageFileName: clip.imageFileName,
                    isSensitive: clip.isSensitive
                )
            )
        }
        guard save(saved, storage: storage) else { return false }
        return saveTemporaryInbox(temporary, storage: storage)
    }

    // MARK: Borrados realizados desde el teclado

    static func recordDeletion(of ids: Set<UUID>, storage: Storage = .live) {
        guard !ids.isEmpty else { return }
        var stored = Set(storage.settingsDefaults?.stringArray(forKey: deletedIDsKey) ?? [])
        stored.formUnion(ids.map(\.uuidString))
        storage.settingsDefaults?.set(Array(stored), forKey: deletedIDsKey)
    }

    static func pendingDeletedIDs(storage: Storage = .live) -> Set<UUID> {
        Set((storage.settingsDefaults?.stringArray(forKey: deletedIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func forgetDeletion(of ids: Set<UUID>, storage: Storage = .live) {
        let remaining = pendingDeletedIDs(storage: storage).subtracting(ids)
        storage.settingsDefaults?.set(remaining.map(\.uuidString), forKey: deletedIDsKey)
    }

    static func consumeDeletedIDs(storage: Storage = .live) -> Set<UUID> {
        let ids = pendingDeletedIDs(storage: storage)
        storage.settingsDefaults?.removeObject(forKey: deletedIDsKey)
        return ids
    }

    // MARK: Carpetas

    static func loadFolders() -> [String] {
        let stored = sharedDefaults?.stringArray(forKey: foldersKey) ?? []
        return stored.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    static func addFolder(_ proposedName: String) -> String? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var folders = loadFolders()
        if let existing = folders.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        folders.append(name)
        sharedDefaults?.set(folders, forKey: foldersKey)
        return name
    }

    static func removeFolder(_ name: String) {
        let folders = loadFolders().filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        sharedDefaults?.set(folders, forKey: foldersKey)

        var clips = load()
        for index in clips.indices where clips[index].folderName == name {
            clips[index].folderName = nil
        }
        save(clips)
    }

    // MARK: Imágenes

    static func imageURL(fileName: String, storage: Storage = .live) -> URL? {
        guard !fileName.isEmpty, fileName != ".", fileName != "..",
              !fileName.contains("/"), !fileName.contains("\\") else { return nil }
        return imagesDirectoryURL(storage: storage)?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func imageData(fileName: String, storage: Storage = .live) -> Data? {
        guard let url = imageURL(fileName: fileName, storage: storage) else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    static func writeImage(_ data: Data, fileName: String, storage: Storage = .live) -> Bool {
        guard let url = imageURL(fileName: fileName, storage: storage) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Publica la imagen de un elemento de la app para que el teclado pueda mostrarla.
    static func storeImageIfNeeded(_ data: Data, for id: UUID, storage: Storage = .live) -> String? {
        let fileName = "\(id.uuidString).jpg"
        guard let url = imageURL(fileName: fileName, storage: storage) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return fileName }
        return writeImage(data, fileName: fileName, storage: storage) ? fileName : nil
    }

    static func removeImage(fileName: String, storage: Storage = .live) {
        guard let url = imageURL(fileName: fileName, storage: storage) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func pruneImages(keeping referenced: Set<String>, storage: Storage = .live) {
        guard let directory = imagesDirectoryURL(storage: storage),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: Utilidades

    static func sort(_ clips: [SharedClipboardClip]) -> [SharedClipboardClip] {
        clips.sorted { first, second in
            if first.isPinned != second.isPinned { return first.isPinned }
            if first.isFavorite != second.isFavorite { return first.isFavorite }
            return first.updatedAt > second.updatedAt
        }
    }

    static func detectKind(_ text: String) -> String {
        if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return "link"
        }
        if text.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "email"
        }
        if text.range(of: #"^\+?[0-9][0-9 ()-]{6,}$"#, options: .regularExpression) != nil {
            return "phone"
        }
        return "text"
    }

    static func symbol(forKind kindRawValue: String) -> String {
        switch kindRawValue {
        case "link": "link"
        case "image": "photo"
        case "email": "envelope"
        case "phone": "phone"
        default: "text.alignleft"
        }
    }

    private static func temporaryExpiration(storage: Storage = .live) -> Date? {
        let value = storage.settingsDefaults?.integer(forKey: "temporaryRetentionHours") ?? 0
        let hours = value == 0 ? 24 : value
        guard hours > 0 else { return nil }
        return Calendar.current.date(byAdding: .hour, value: hours, to: .now)
    }

    private static func saveTrimmedTemporaryInbox(_ clips: [SharedTemporaryClip], maximumItems: Int, storage: Storage = .live) -> Bool {
        var imageCount = 0
        var kept: [SharedTemporaryClip] = []
        var dropped: [SharedTemporaryClip] = []
        for clip in clips.sorted(by: { $0.capturedAt > $1.capturedAt }) {
            if clip.isImage { imageCount += 1 }
            if kept.count < max(1, maximumItems), !(clip.isImage && imageCount > maximumTemporaryImages) {
                kept.append(clip)
            } else {
                dropped.append(clip)
            }
        }
        guard saveTemporaryInbox(kept, storage: storage) else { return false }
        dropped.compactMap(\.imageFileName).forEach { removeImage(fileName: $0, storage: storage) }
        return true
    }

    /// La carpeta del App Group se pregunta a iOS una sola vez (es una consulta al sistema y se
    /// hacía en cada lectura del historial y en cada redibujado de los ajustes).
    private static let cachedContainerURL: URL? =
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)

    private static let cachedLocalDirectoryURL: URL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("SuperTecladoClipboard", isDirectory: true)

    private static func containerURL() -> URL? {
        cachedContainerURL
    }

    private static func historyURL(storage: Storage = .live) -> URL? {
        storage.directoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func temporaryInboxURL(storage: Storage = .live) -> URL? {
        storage.directoryURL?.appendingPathComponent(temporaryInboxFileName, isDirectory: false)
    }

    private static func imagesDirectoryURL(storage: Storage = .live) -> URL? {
        let url = (storage.directoryURL ?? storage.localDirectoryURL)
            .appendingPathComponent(imagesDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    @discardableResult
    private static func saveTemporaryInbox(_ clips: [SharedTemporaryClip], storage: Storage = .live) -> Bool {
        if let url = temporaryInboxURL(storage: storage) { return encodeFile(clips, at: url) }
        return encodeDefaults(clips, forKey: temporaryFallbackKey, storage: storage)
    }

    /// El archivo del App Group es la fuente de verdad. La copia de UserDefaults es local a cada
    /// proceso, así que solo se usa si el contenedor compartido no existe;
    /// de lo contrario reaparecerían elementos borrados desde la app o el teclado.
    private static func readList<Value: Decodable>(at url: URL?, fallbackKey: String, storage: Storage = .live) -> [Value] {
        if let url { return decodeFile(at: url) ?? [] }
        return decodeDefaults(forKey: fallbackKey, storage: storage) ?? []
    }

    private static func decodeFile<Value: Decodable>(at url: URL?) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    @discardableResult
    private static func encodeFile<Value: Encodable>(_ value: Value, at url: URL?) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    private static func decodeDefaults<Value: Decodable>(forKey key: String, storage: Storage = .live) -> Value? {
        guard let data = storage.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    @discardableResult
    private static func encodeDefaults<Value: Encodable>(_ value: Value, forKey key: String, storage: Storage = .live) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        storage.defaults.set(data, forKey: key)
        return true
    }

    private static func canReadList<Value: Decodable>(
        _ type: Value.Type, at url: URL?, fallbackKey: String, storage: Storage
    ) -> Bool {
        if let url {
            if !FileManager.default.fileExists(atPath: url.path) { return true }
            let values: [Value]? = decodeFile(at: url)
            return values != nil
        }
        guard let data = storage.defaults.data(forKey: fallbackKey) else { return true }
        return (try? JSONDecoder().decode([Value].self, from: data)) != nil
    }
}
