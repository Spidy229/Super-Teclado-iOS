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
}

enum SharedClipboardStore {
    static let appGroupID = "group.com.spidy229.superteclado"
    private static let fileName = "super-teclado-history.json"
    private static let temporaryInboxFileName = "super-teclado-temporary-inbox.json"
    private static let foldersKey = "super-teclado-folders"
    private static let lastCapturedChangeCountKey = "super-teclado-last-captured-change-count"

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
        guard let url = historyURL(),
              let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([SharedClipboardClip].self, from: data) else {
            return []
        }
        return sort(clips)
    }

    static func save(_ clips: [SharedClipboardClip]) {
        guard let url = historyURL(),
              let data = try? JSONEncoder().encode(sort(clips)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func captureTemporaryText(
        _ text: String,
        pasteboardChangeCount: Int,
        maximumItems: Int? = nil
    ) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        let defaults = UserDefaults(suiteName: appGroupID)
        if defaults?.integer(forKey: lastCapturedChangeCountKey) == pasteboardChangeCount,
           defaults?.object(forKey: lastCapturedChangeCountKey) != nil {
            return false
        }

        var clips = loadTemporaryInbox()
        if let index = clips.firstIndex(where: { $0.text == value }) {
            clips[index].capturedAt = .now
        } else {
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
                    )
                )
            )
        }

        clips.sort { $0.capturedAt > $1.capturedAt }
        saveTemporaryInbox(Array(clips.prefix(maximumItems ?? maximumTemporaryItems)))
        defaults?.set(pasteboardChangeCount, forKey: lastCapturedChangeCountKey)
        return true
    }

    static func loadTemporaryInbox() -> [SharedTemporaryClip] {
        guard let url = temporaryInboxURL(),
              let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([SharedTemporaryClip].self, from: data) else {
            return []
        }
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
        guard let url = temporaryInboxURL(),
              let data = try? JSONEncoder().encode(clips) else { return }
        try? data.write(to: url, options: .atomic)
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

