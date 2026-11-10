import Darwin
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

    // Explicit storage locations let regression tests use private directories and suites.
    // The app and extension must never merge their separate defaults over shared deletions.
    struct Storage {
        let directoryURL: URL?
        let fallbackDefaults: UserDefaults
        let settingsDefaults: UserDefaults?

        static var live: Storage {
            Storage(
                directoryURL: FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: appGroupID
                ),
                fallbackDefaults: .standard,
                settingsDefaults: UserDefaults(suiteName: appGroupID)
            )
        }
    }

    private struct PasteboardEvent: Codable {
        let changeCount: Int
        let bootSession: String?
    }

    private struct TemporaryInboxState: Codable {
        var clips: [SharedTemporaryClip]
        var lastPasteboardEvent: PasteboardEvent?
    }

    static var automaticCaptureEnabled: Bool {
        boolSetting("automaticCaptureEnabled", storage: .live)
    }

    static var skipOneTimeCodes: Bool {
        boolSetting("skipOneTimeCodes", storage: .live)
    }

    static var temporaryRetentionHours: Int {
        positiveSetting("temporaryRetentionHours", defaultValue: 24, storage: .live)
    }

    static var maximumTemporaryItems: Int {
        positiveSetting("maximumTemporaryItems", defaultValue: 50, storage: .live)
    }

    static func canRead(storage: Storage = .live) -> Bool {
        readSaved(storage: storage) != nil && readTemporaryState(storage: storage) != nil
    }

    static func load(storage: Storage = .live) -> [SharedClipboardClip] {
        sort(readSaved(storage: storage) ?? [])
    }

    @discardableResult
    static func save(_ clips: [SharedClipboardClip], storage: Storage = .live) -> Bool {
        write(sort(clips), fileName: fileName, fallbackKey: savedFallbackKey, storage: storage)
    }

    // The event survives promotion, deletion and expiry. Its boot identity prevents an
    // old counter from suppressing a different copy after the device restarts.
    static func shouldCapture(pasteboardChangeCount: Int, storage: Storage = .live) -> Bool {
        guard let state = readTemporaryState(storage: storage) else { return false }
        return !isSameEvent(state.lastPasteboardEvent, changeCount: pasteboardChangeCount)
    }

    // The main app records an accepted copy after persisting its SwiftData history.
    // Explicit events avoid mistaking use/reordering of an older clip for a new copy.
    @discardableResult
    static func rememberPasteboardEvent(changeCount: Int, storage: Storage = .live) -> Bool {
        guard var state = readTemporaryState(storage: storage) else { return false }
        state.lastPasteboardEvent = PasteboardEvent(changeCount: changeCount, bootSession: bootSessionID())
        return writeTemporaryState(state, storage: storage)
    }

    @discardableResult
    static func captureTemporaryText(
        _ text: String,
        pasteboardChangeCount: Int,
        maximumItems: Int? = nil,
        storage: Storage = .live
    ) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var state = readTemporaryState(storage: storage),
              !isSameEvent(state.lastPasteboardEvent, changeCount: pasteboardChangeCount) else {
            return false
        }

        let now = Date.now
        state.clips = liveTemporaryClips(state.clips, at: now)
        state.clips.insert(
            SharedTemporaryClip(
                id: UUID(),
                text: text,
                capturedAt: now,
                kindRawValue: detectKind(text),
                expiresAt: Calendar.current.date(
                    byAdding: .hour,
                    value: positiveSetting("temporaryRetentionHours", defaultValue: 24, storage: storage),
                    to: now
                ),
                pasteboardChangeCount: pasteboardChangeCount
            ),
            at: 0
        )
        let limit = maximumItems ?? positiveSetting(
            "maximumTemporaryItems", defaultValue: 50, storage: storage
        )
        state.clips = Array(state.clips.prefix(max(1, limit)))
        state.lastPasteboardEvent = PasteboardEvent(
            changeCount: pasteboardChangeCount,
            bootSession: bootSessionID()
        )
        return writeTemporaryState(state, storage: storage)
    }

    static func loadTemporaryInbox(storage: Storage = .live) -> [SharedTemporaryClip] {
        liveTemporaryClips(readTemporaryState(storage: storage)?.clips ?? [], at: .now)
    }

    @discardableResult
    static func clearTemporaryInbox(storage: Storage = .live) -> Bool {
        replaceTemporaryInbox([], storage: storage)
    }

    @discardableResult
    static func replaceTemporaryInbox(
        _ clips: [SharedTemporaryClip],
        lastPasteboardChangeCount: Int? = nil,
        storage: Storage = .live
    ) -> Bool {
        guard var state = readTemporaryState(storage: storage) else { return false }
        state.clips = clips.sorted { $0.capturedAt > $1.capturedAt }
        if let lastPasteboardChangeCount {
            state.lastPasteboardEvent = PasteboardEvent(
                changeCount: lastPasteboardChangeCount, bootSession: bootSessionID()
            )
        }
        return writeTemporaryState(state, storage: storage)
    }

    static func markTemporaryUsed(id: UUID, storage: Storage = .live) {
        guard var state = readTemporaryState(storage: storage),
              let index = state.clips.firstIndex(where: { $0.id == id }) else { return }
        state.clips[index].capturedAt = .now
        _ = writeTemporaryState(state, storage: storage)
    }

    @discardableResult
    static func promoteTemporary(id: UUID, storage: Storage = .live) -> Bool {
        guard var state = readTemporaryState(storage: storage),
              let clip = liveTemporaryClips(state.clips, at: .now).first(where: { $0.id == id }),
              var saved = readSaved(storage: storage) else { return false }

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
        // Preserve the temporary copy if saving the permanent one fails.
        guard save(saved, storage: storage) else { return false }
        state.clips.removeAll { $0.id == id }
        return writeTemporaryState(state, storage: storage)
    }

    static func addCopiedText(
        _ text: String, maximumItems: Int = 250, storage: Storage = .live
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var clips = readSaved(storage: storage) else { return }

        if let index = clips.firstIndex(where: { $0.text == text }) {
            clips[index].updatedAt = .now
        } else {
            clips.append(
                SharedClipboardClip(
                    id: UUID(),
                    text: text,
                    createdAt: .now,
                    updatedAt: .now,
                    kindRawValue: detectKind(text),
                    isFavorite: false,
                    isPinned: false
                )
            )
        }
        save(Array(sort(clips).prefix(max(1, maximumItems))), storage: storage)
    }

    static func toggleFavorite(id: UUID, storage: Storage = .live) {
        guard var clips = readSaved(storage: storage),
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].isFavorite.toggle()
        clips[index].updatedAt = .now
        save(clips, storage: storage)
    }

    static func markUsed(id: UUID, storage: Storage = .live) {
        guard var clips = readSaved(storage: storage),
              let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].updatedAt = .now
        save(clips, storage: storage)
    }

    static func loadFolders(storage: Storage = .live) -> [String] {
        let stored = storage.settingsDefaults?.stringArray(forKey: foldersKey) ?? []
        return stored.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    static func addFolder(_ proposedName: String, storage: Storage = .live) -> String? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var folders = loadFolders(storage: storage)
        if let existing = folders.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        folders.append(name)
        storage.settingsDefaults?.set(folders, forKey: foldersKey)
        return name
    }

    static func removeFolder(_ name: String, storage: Storage = .live) {
        let folders = loadFolders(storage: storage).filter {
            $0.caseInsensitiveCompare(name) != .orderedSame
        }
        storage.settingsDefaults?.set(folders, forKey: foldersKey)

        guard var clips = readSaved(storage: storage) else { return }
        for index in clips.indices where clips[index].folderName == name {
            clips[index].folderName = nil
        }
        save(clips, storage: storage)
    }

    static func sort(_ clips: [SharedClipboardClip]) -> [SharedClipboardClip] {
        clips.sorted { first, second in
            if first.isPinned != second.isPinned { return first.isPinned }
            if first.isFavorite != second.isFavorite { return first.isFavorite }
            return first.updatedAt > second.updatedAt
        }
    }

    private static func boolSetting(_ key: String, storage: Storage) -> Bool {
        guard storage.settingsDefaults?.object(forKey: key) != nil else { return true }
        return storage.settingsDefaults?.bool(forKey: key) ?? true
    }

    private static func positiveSetting(_ key: String, defaultValue: Int, storage: Storage) -> Int {
        let value = storage.settingsDefaults?.integer(forKey: key) ?? 0
        return value > 0 ? value : defaultValue
    }

    private static func readSaved(storage: Storage) -> [SharedClipboardClip]? {
        guard let data = readData(fileName: fileName, fallbackKey: savedFallbackKey, storage: storage) else {
            return nil
        }
        if data.isEmpty { return [] }
        return try? JSONDecoder().decode([SharedClipboardClip].self, from: data)
    }

    private static func readTemporaryState(storage: Storage) -> TemporaryInboxState? {
        guard let data = readData(
            fileName: temporaryInboxFileName, fallbackKey: temporaryFallbackKey, storage: storage
        ) else { return nil }
        if data.isEmpty { return TemporaryInboxState(clips: [], lastPasteboardEvent: nil) }
        let decoder = JSONDecoder()
        if let state = try? decoder.decode(TemporaryInboxState.self, from: data) { return state }
        // Older releases stored an array without a durable event marker.
        guard let clips = try? decoder.decode([SharedTemporaryClip].self, from: data) else { return nil }
        let latest = clips.filter { $0.pasteboardChangeCount != nil }
            .max { $0.capturedAt < $1.capturedAt }
        return TemporaryInboxState(
            clips: clips,
            lastPasteboardEvent: latest?.pasteboardChangeCount.map {
                PasteboardEvent(changeCount: $0, bootSession: bootSessionID())
            }
        )
    }

    private static func liveTemporaryClips(
        _ clips: [SharedTemporaryClip], at now: Date
    ) -> [SharedTemporaryClip] {
        clips.filter { $0.expiresAt.map { $0 > now } ?? true }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func writeTemporaryState(_ state: TemporaryInboxState, storage: Storage) -> Bool {
        write(state, fileName: temporaryInboxFileName, fallbackKey: temporaryFallbackKey, storage: storage)
    }

    // A reachable group container is authoritative, including an empty/missing file.
    // Unreadable/corrupt files never trigger recovery from another process's stale defaults.
    // nil signals an I/O failure so read-modify-write operations leave that file intact.
    private static func readData(fileName: String, fallbackKey: String, storage: Storage) -> Data? {
        if let directoryURL = storage.directoryURL {
            let url = directoryURL.appendingPathComponent(fileName, isDirectory: false)
            do {
                let data = try Data(contentsOf: url)
                storage.fallbackDefaults.removeObject(forKey: fallbackKey)
                return data
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                storage.fallbackDefaults.removeObject(forKey: fallbackKey)
                return Data()
            } catch {
                return nil
            }
        }
        return storage.fallbackDefaults.data(forKey: fallbackKey) ?? Data()
    }

    @discardableResult
    private static func write<Value: Encodable>(
        _ value: Value, fileName: String, fallbackKey: String, storage: Storage
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        if let directoryURL = storage.directoryURL {
            do {
                try data.write(
                    to: directoryURL.appendingPathComponent(fileName, isDirectory: false),
                    options: .atomic
                )
                storage.fallbackDefaults.removeObject(forKey: fallbackKey)
                return true
            } catch {
                return false
            }
        }
        storage.fallbackDefaults.set(data, forKey: fallbackKey)
        return true
    }

    private static func isSameEvent(_ event: PasteboardEvent?, changeCount: Int) -> Bool {
        event?.changeCount == changeCount && event?.bootSession == bootSessionID()
    }

    private static func bootSessionID() -> String? {
        var bootTime = timeval(tv_sec: 0, tv_usec: 0)
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
        return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
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


