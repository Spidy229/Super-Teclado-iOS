import Foundation
import SwiftData

/// Copia de seguridad en un archivo JSON: historial, carpetas, diccionario personal y ajustes.
/// Sirve para no perder nada al volver a instalar la app con otro certificado.
struct SuperTecladoBackup: Codable {
    var version = 1
    var createdAt: Date
    var appVersion: String
    var items: [BackupItem]
    var folders: [String]
    var learnedWords: [String: Int]
    var learnedBigrams: [String: [String: Int]]
    var shortcuts: [String: String]
    var sharedSettings: [String: BackupValue]
    var appSettings: [String: BackupValue]
}

struct BackupItem: Codable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var text: String?
    var imageData: Data?
    var recognizedText: String?
    var kindRawValue: String
    var isFavorite: Bool
    var isPinned: Bool
    var tagsText: String
    var folderName: String?
    var colorTagRawValue: String?
    var contentHash: String
    var isTemporary: Bool
    var expiresAt: Date?
    var isSensitive: Bool
}

enum BackupValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init?(_ value: Any) {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number as CFNumber) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        } else if let string = value as? String {
            self = .string(string)
        } else {
            return nil
        }
    }

    var value: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        }
    }
}

struct BackupImportSummary {
    var items = 0
    var skipped = 0
    var words = 0
    var shortcuts = 0
}

@MainActor
enum BackupService {
    /// Ajustes de la app que no están en el App Group.
    private static let appSettingKeys = ["localClipboardOnly", "maximumItems", "autoDeleteDays", "requireBiometrics"]

    /// Ajustes del App Group que se copian (sin datos de diagnóstico ni contadores).
    private static let extraSharedKeys = [
        SharedClipboardStore.automaticCaptureKey,
        "skipOneTimeCodes",
        "temporaryRetentionHours",
        "maximumTemporaryItems",
        SharedClipboardStore.sensitiveModeKey
    ]

    private static let excludedSharedKeys: Set<String> = [
        KeyboardPreferenceKey.learnedWords,
        KeyboardPreferenceKey.learnedBigrams,
        KeyboardPreferenceKey.personalShortcuts,
        KeyboardPreferenceKey.lastActive
    ]

    static func makeBackup(from context: ModelContext, includeImages: Bool) -> SuperTecladoBackup {
        let models = (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []
        let items = models.compactMap { item -> BackupItem? in
            if item.imageData != nil && !includeImages && item.text == nil { return nil }
            return BackupItem(
                id: item.id,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                text: item.text,
                imageData: includeImages ? item.imageData : nil,
                recognizedText: item.recognizedText,
                kindRawValue: item.kindRawValue,
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                tagsText: item.tagsText,
                folderName: item.folderName,
                colorTagRawValue: item.colorTagRawValue,
                contentHash: item.contentHash,
                isTemporary: item.isTemporary,
                expiresAt: item.expiresAt,
                isSensitive: item.isSensitive
            )
        }

        var sharedSettings: [String: BackupValue] = [:]
        let shared = SharedClipboardStore.sharedDefaults?.dictionaryRepresentation() ?? [:]
        for (key, value) in shared {
            let isKeyboardSetting = key.hasPrefix("keyboard") && !excludedSharedKeys.contains(key)
            guard isKeyboardSetting || extraSharedKeys.contains(key), let backupValue = BackupValue(value) else { continue }
            sharedSettings[key] = backupValue
        }

        var appSettings: [String: BackupValue] = [:]
        for key in appSettingKeys {
            if let value = UserDefaults.standard.object(forKey: key), let backupValue = BackupValue(value) {
                appSettings[key] = backupValue
            }
        }

        return SuperTecladoBackup(
            createdAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            items: items,
            folders: SharedClipboardStore.loadFolders(),
            learnedWords: PersonalDictionary.learnedWords(),
            learnedBigrams: PersonalDictionary.learnedBigrams(),
            shortcuts: PersonalDictionary.shortcuts(),
            sharedSettings: sharedSettings,
            appSettings: appSettings
        )
    }

    /// Añade a lo que ya hay lo que contiene la copia, sin duplicar elementos.
    static func restore(_ backup: SuperTecladoBackup, into context: ModelContext) throws -> BackupImportSummary {
        var summary = BackupImportSummary()
        let existing = (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []
        var knownIDs = Set(existing.map(\.id))
        var knownHashes = Set(existing.map(\.contentHash))

        for item in backup.items {
            guard !knownIDs.contains(item.id), !knownHashes.contains(item.contentHash) else {
                summary.skipped += 1
                continue
            }
            if item.isTemporary, let expiresAt = item.expiresAt, expiresAt <= .now {
                summary.skipped += 1
                continue
            }
            context.insert(
                ClipboardItem(
                    id: item.id,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    text: item.text,
                    imageData: item.imageData,
                    recognizedText: item.recognizedText,
                    kind: ClipboardKind(rawValue: item.kindRawValue) ?? .text,
                    isFavorite: item.isFavorite,
                    isPinned: item.isPinned,
                    tagsText: item.tagsText,
                    folderName: item.folderName,
                    colorTagRawValue: item.colorTagRawValue,
                    contentHash: item.contentHash,
                    isTemporary: item.isTemporary,
                    expiresAt: item.expiresAt,
                    isSensitive: item.isSensitive
                )
            )
            knownIDs.insert(item.id)
            knownHashes.insert(item.contentHash)
            summary.items += 1
        }

        backup.folders.forEach { SharedClipboardStore.addFolder($0) }

        var words = PersonalDictionary.learnedWords()
        for (word, count) in backup.learnedWords {
            if (words[word] ?? 0) < count { summary.words += 1 }
            words[word] = max(words[word] ?? 0, count)
        }
        PersonalDictionary.saveLearnedWords(words)

        var bigrams = PersonalDictionary.learnedBigrams()
        for (first, followers) in backup.learnedBigrams {
            var merged = bigrams[first] ?? [:]
            for (second, count) in followers { merged[second] = max(merged[second] ?? 0, count) }
            bigrams[first] = merged
        }
        PersonalDictionary.saveLearnedBigrams(bigrams)

        for (shortcut, phrase) in backup.shortcuts where PersonalDictionary.setShortcut(shortcut, phrase: phrase) {
            summary.shortcuts += 1
        }

        for (key, value) in backup.sharedSettings {
            SharedClipboardStore.sharedDefaults?.set(value.value, forKey: key)
        }
        for (key, value) in backup.appSettings where appSettingKeys.contains(key) {
            UserDefaults.standard.set(value.value, forKey: key)
        }

        try KeyboardHistorySync.commit(context)
        return summary
    }

    /// Codifica fuera del hilo principal (con imágenes, la copia puede ocupar decenas de MB).
    nonisolated static func encodeDetached(_ backup: SuperTecladoBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> SuperTecladoBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SuperTecladoBackup.self, from: data)
    }
}
