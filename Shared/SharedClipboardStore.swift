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

    var kindSymbol: String {
        switch kindRawValue {
        case "link": "link"
        case "image": "photo"
        case "email": "envelope"
        case "phone": "phone"
        default: "text.alignleft"
        }
    }
}

struct SharedTemporaryClip: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var capturedAt: Date
    var kindRawValue: String
    var expiresAt: Date?
    var pasteboardChangeCount: Int? = nil
}

enum SharedClipboardStore {
    static let appGroupID = "group.com.spidy229.superteclado"
    private static let fileName = "super-teclado-history.json"
    private static let temporaryInboxFileName = "super-teclado-temporary-inbox.json"
    private static let foldersKey = "super-teclado-folders"
    private static let savedFallbackKey = "super-teclado-saved-fallback"
    private static let temporaryFallbackKey = "super-teclado-temporary-fallback"

    static var automaticCaptureEnabled: Bool {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard defaults?.object(forKey: "automaticCaptureEnabled") != nil else { return true }
        return defaults?.bool(forKey: "automaticCaptureEnabled") ?? true
    }

    static var skipOneTimeCodes: Bool {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard defaults?.object(forKey: "skipOneTimeCodes") != nil else { return true }
        return defaults?.bool(forKey: "skipOneTimeCodes") ?? true
    }

    static var temporaryRetentionHours: Int {
        let value = UserDefaults(suiteName: appGroupID)?.integer(forKey: "temporaryRetentionHours") ?? 0
        return value > 0 ? value : 24
    }

    static var maximumTemporaryItems: Int {
        let value = UserDefaults(suiteName: appGroupID)?.integer(forKey: "maximumTemporaryItems") ?? 0
        return value > 0 ? value : 50
    }

    static func load() -> [SharedClipboardClip] {
        let fileClips: [SharedClipboardClip] = decodeFile(at: historyURL()) ?? []
        let fallbackClips: [SharedClipboardClip] = decodeDefaults(forKey: savedFallbackKey) ?? []
        return sort(mergeSaved(fileClips + fallbackClips))
    }

    static func save(_ clips: [SharedClipboardClip]) {
        let sorted = sort(clips)
        encodeFile(sorted, at: historyURL())
        encodeDefaults(sorted, forKey: savedFallbackKey)
    }

    @discardableResult
    static func captureTemporaryText(
        _ text: String,
        pasteboardChangeCount: Int,
        maximumItems: Int? = nil
    ) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        var clips = loadTemporaryInbox()
        if clips.contains(where: { $0.pasteboardChangeCount == pasteboardChangeCount }) {
            return false
        }

        clips.append(
            SharedTemporaryClip(
                id: UUID(),
                text: value,
                capturedAt: .now,
                kindRawValue: detectKind(value),
                expiresAt: Calendar.current.date(
                    byAdding: .hour,
                    value: temporaryRetentionHours,
                    to: .now
                ),
                pasteboardChangeCount: pasteboardChangeCount
            )
        )

        clips.sort { $0.capturedAt > $1.capturedAt }
        saveTemporaryInbox(Array(clips.prefix(maximumItems ?? maximumTemporaryItems)))
        return true
    }

    static func loadTemporaryInbox() -> [SharedTemporaryClip] {
        let fileClips: [SharedTemporaryClip] = decodeFile(at: temporaryInboxURL()) ?? []
        let fallbackClips: [SharedTemporaryClip] = decodeDefaults(forKey: temporaryFallbackKey) ?? []
        return mergeTemporary(fileClips + fallbackClips)
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
    static func promoteTemporary(id: UUID) -> Bool {
        var temporary = loadTemporaryInbox()
        guard let index = temporary.firstIndex(where: { $0.id == id }) else { return false }
        let clip = temporary.remove(at: index)

        var saved = load()
        if let existingIndex = saved.firstIndex(where: { $0.text == clip.text }) {
            saved[existingIndex].updatedAt = .now
        } else {
            saved.append(
                SharedClipboardClip(
                    id: clip.id,
                    text: clip.text,
                    createdAt: clip.capturedAt,
                    updatedAt: .now,
                    kindRawValue: clip.kindRawValue,
                    isFavorite: false,
                    isPinned: true
                )
            )
        }
        saveTemporaryInbox(temporary)
        save(saved)
        return true
    }

    static func addCopiedText(_ text: String, maximumItems: Int = 250) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        var clips = load()
        if let index = clips.firstIndex(where: { $0.text == value }) {
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

    static func loadFolders() -> [String] {
        let stored = UserDefaults(suiteName: appGroupID)?.stringArray(forKey: foldersKey) ?? []
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
        UserDefaults(suiteName: appGroupID)?.set(folders, forKey: foldersKey)
        return name
    }

    static func removeFolder(_ name: String) {
        let folders = loadFolders().filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        UserDefaults(suiteName: appGroupID)?.set(folders, forKey: foldersKey)

        var clips = load()
        for index in clips.indices where clips[index].folderName == name {
            clips[index].folderName = nil
        }
        save(clips)
    }

    static func sort(_ clips: [SharedClipboardClip]) -> [SharedClipboardClip] {
        clips.sorted { first, second in
            if first.isPinned != second.isPinned { return first.isPinned }
            if first.isFavorite != second.isFavorite { return first.isFavorite }
            return first.updatedAt > second.updatedAt
        }
    }

    private static func historyURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func temporaryInboxURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(temporaryInboxFileName, isDirectory: false)
    }

    private static func saveTemporaryInbox(_ clips: [SharedTemporaryClip]) {
        encodeFile(clips, at: temporaryInboxURL())
        encodeDefaults(clips, forKey: temporaryFallbackKey)
    }

    private static func mergeSaved(_ clips: [SharedClipboardClip]) -> [SharedClipboardClip] {
        Dictionary(grouping: clips, by: \.id)
            .compactMap { $0.value.max(by: { $0.updatedAt < $1.updatedAt }) }
    }

    private static func mergeTemporary(_ clips: [SharedTemporaryClip]) -> [SharedTemporaryClip] {
        Dictionary(grouping: clips, by: \.id)
            .compactMap { $0.value.max(by: { $0.capturedAt < $1.capturedAt }) }
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

    private static func detectKind(_ text: String) -> String {
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
}


