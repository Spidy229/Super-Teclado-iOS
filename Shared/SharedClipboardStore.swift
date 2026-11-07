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

    // MARK: Guardados

    static func load() -> [SharedClipboardClip] {
        sort(readList(at: historyURL(), fallbackKey: savedFallbackKey))
    }

    static func save(_ clips: [SharedClipboardClip]) {
        let sorted = sort(clips)
        encodeFile(sorted, at: historyURL())
        encodeDefaults(sorted, forKey: savedFallbackKey)
    }

    static func addCopiedText(_ text: String, maximumItems: Int = 250) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

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
        if removeImages { removed.compactMap(\.imageFileName).forEach(removeImage(fileName:)) }
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
    static func demoteSaved(id: UUID) -> Bool {
        var clips = load()
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        let clip = clips.remove(at: index)
        save(clips)
        recordDeletion(of: [id])

        var temporary = loadTemporaryInbox()
        temporary.removeAll { existing in
            clip.isImage ? existing.imageFileName == clip.imageFileName : existing.text == clip.text
        }
        temporary.append(
            SharedTemporaryClip(
                id: UUID(),
                text: clip.text,
                capturedAt: .now,
                kindRawValue: clip.kindRawValue,
                expiresAt: temporaryExpiration(),
                imageFileName: clip.imageFileName
            )
        )
        saveTemporaryInbox(temporary)
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
        isSensitive: Bool = false
    ) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        var clips = loadTemporaryInbox()
        if let pasteboardChangeCount,
           clips.contains(where: { $0.pasteboardChangeCount == pasteboardChangeCount }) {
            return false
        }
        let expiration = isSensitive
            ? Date.now.addingTimeInterval(ClipboardClassifier.sensitiveLifetime)
            : temporaryExpiration()
        if load().contains(where: { !$0.isImage && $0.text == value }) {
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

        saveTrimmedTemporaryInbox(clips, maximumItems: maximumItems ?? maximumTemporaryItems)
        return true
    }

    @discardableResult
    static func captureTemporaryImage(
        _ data: Data,
        hash: String,
        pasteboardChangeCount: Int?,
        maximumItems: Int? = nil
    ) -> Bool {
        var clips = loadTemporaryInbox()
        if let pasteboardChangeCount,
           clips.contains(where: { $0.pasteboardChangeCount == pasteboardChangeCount }) {
            return false
        }

        if let index = clips.firstIndex(where: { $0.imageHash == hash }) {
            clips[index].capturedAt = .now
            clips[index].expiresAt = temporaryExpiration()
            clips[index].pasteboardChangeCount = pasteboardChangeCount
        } else {
            let id = UUID()
            let imageFileName = "\(id.uuidString).jpg"
            guard writeImage(data, fileName: imageFileName) else { return false }
            clips.append(
                SharedTemporaryClip(
                    id: id,
                    text: "",
                    capturedAt: .now,
                    kindRawValue: "image",
                    expiresAt: temporaryExpiration(),
                    pasteboardChangeCount: pasteboardChangeCount,
                    imageFileName: imageFileName,
                    imageHash: hash
                )
            )
        }

        saveTrimmedTemporaryInbox(clips, maximumItems: maximumItems ?? maximumTemporaryItems)
        return true
    }

    static func loadTemporaryInbox() -> [SharedTemporaryClip] {
        let clips: [SharedTemporaryClip] = readList(at: temporaryInboxURL(), fallbackKey: temporaryFallbackKey)
        return clips
            .filter { $0.expiresAt.map { $0 > .now } ?? true }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    static func clearTemporaryInbox() {
        saveTemporaryInbox([])
    }

    static func replaceTemporaryInbox(_ clips: [SharedTemporaryClip]) {
        saveTemporaryInbox(clips.sorted { $0.capturedAt > $1.capturedAt })
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
        if removeImages { removed.compactMap(\.imageFileName).forEach(removeImage(fileName:)) }
        return removed
    }

    @discardableResult
    static func promoteTemporary(id: UUID) -> Bool {
        var temporary = loadTemporaryInbox()
        guard let index = temporary.firstIndex(where: { $0.id == id }) else { return false }
        let clip = temporary.remove(at: index)

        var saved = load()
        if !clip.isImage, let existingIndex = saved.firstIndex(where: { !$0.isImage && $0.text == clip.text }) {
            saved[existingIndex].updatedAt = .now
            saved[existingIndex].isPinned = true
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
                    imageFileName: clip.imageFileName
                )
            )
        }
        saveTemporaryInbox(temporary)
        save(saved)
        return true
    }

    // MARK: Borrados realizados desde el teclado

    static func recordDeletion(of ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var stored = Set(sharedDefaults?.stringArray(forKey: deletedIDsKey) ?? [])
        stored.formUnion(ids.map(\.uuidString))
        sharedDefaults?.set(Array(stored), forKey: deletedIDsKey)
    }

    static func pendingDeletedIDs() -> Set<UUID> {
        Set((sharedDefaults?.stringArray(forKey: deletedIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func forgetDeletion(of ids: Set<UUID>) {
        let remaining = pendingDeletedIDs().subtracting(ids)
        sharedDefaults?.set(remaining.map(\.uuidString), forKey: deletedIDsKey)
    }

    static func consumeDeletedIDs() -> Set<UUID> {
        let ids = pendingDeletedIDs()
        sharedDefaults?.removeObject(forKey: deletedIDsKey)
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

    static func imageURL(fileName: String) -> URL? {
        imagesDirectoryURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func imageData(fileName: String) -> Data? {
        guard let url = imageURL(fileName: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    static func writeImage(_ data: Data, fileName: String) -> Bool {
        guard let url = imageURL(fileName: fileName) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Publica la imagen de un elemento de la app para que el teclado pueda mostrarla.
    static func storeImageIfNeeded(_ data: Data, for id: UUID) -> String? {
        let fileName = "\(id.uuidString).jpg"
        guard let url = imageURL(fileName: fileName) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) { return fileName }
        return writeImage(data, fileName: fileName) ? fileName : nil
    }

    static func removeImage(fileName: String) {
        guard let url = imageURL(fileName: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func pruneImages(keeping referenced: Set<String>) {
        guard let directory = imagesDirectoryURL(),
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

    private static func temporaryExpiration() -> Date? {
        let hours = temporaryRetentionHours
        guard hours > 0 else { return nil }
        return Calendar.current.date(byAdding: .hour, value: hours, to: .now)
    }

    private static func saveTrimmedTemporaryInbox(_ clips: [SharedTemporaryClip], maximumItems: Int) {
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
        saveTemporaryInbox(kept)
        dropped.compactMap(\.imageFileName).forEach(removeImage(fileName:))
    }

    /// La carpeta del App Group se pregunta a iOS una sola vez (es una consulta al sistema y se
    /// hacía en cada lectura del historial y en cada redibujado de los ajustes).
    private static let cachedContainerURL: URL? =
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)

    private static func containerURL() -> URL? {
        cachedContainerURL
    }

    private static func historyURL() -> URL? {
        containerURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func temporaryInboxURL() -> URL? {
        containerURL()?.appendingPathComponent(temporaryInboxFileName, isDirectory: false)
    }

    private static func imagesDirectoryURL() -> URL? {
        guard let url = containerURL()?.appendingPathComponent(imagesDirectoryName, isDirectory: true) else {
            return nil
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func saveTemporaryInbox(_ clips: [SharedTemporaryClip]) {
        encodeFile(clips, at: temporaryInboxURL())
        encodeDefaults(clips, forKey: temporaryFallbackKey)
    }

    /// El archivo del App Group es la fuente de verdad. La copia de UserDefaults es local a cada
    /// proceso, así que solo se usa si el contenedor compartido no existe o el archivo no se puede leer;
    /// de lo contrario reaparecerían elementos borrados desde la app o el teclado.
    private static func readList<Value: Decodable>(at url: URL?, fallbackKey: String) -> [Value] {
        if let url, FileManager.default.fileExists(atPath: url.path),
           let values: [Value] = decodeFile(at: url) {
            return values
        }
        return decodeDefaults(forKey: fallbackKey) ?? []
    }

    private static func decodeFile<Value: Decodable>(at url: URL?) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func encodeFile<Value: Encodable>(_ value: Value, at url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func decodeDefaults<Value: Decodable>(forKey key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func encodeDefaults<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
