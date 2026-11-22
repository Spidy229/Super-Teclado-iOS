import Foundation

/// Diccionario personal compartido entre la app y el teclado: palabras aprendidas, pares de
/// palabras para predecir la siguiente y atajos («qtal» → «¿Qué tal?»).
/// Las palabras y bigramas se guardan en ficheros JSON para no engordar `UserDefaults`.
enum PersonalDictionary {
    /// Veces que debe aparecer una palabra para que se considere correcta.
    static let knownThreshold = 2

    private static let learnedWordsFileName = "super-teclado-learned-words.json"
    private static let learnedBigramsFileName = "super-teclado-learned-bigrams.json"
    private static var defaults: UserDefaults? { SharedClipboardStore.sharedDefaults }

    private static func fileURL(name: String, storage: SharedClipboardStore.Storage) -> URL {
        SharedClipboardStore.storageDirectoryURL(storage: storage)
            .appendingPathComponent(name, isDirectory: false)
    }

    static func learnedWords(storage: SharedClipboardStore.Storage = .live) -> [String: Int] {
        let url = fileURL(name: learnedWordsFileName, storage: storage)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            return decoded
        }
        return storage.settingsDefaults?.dictionary(forKey: KeyboardPreferenceKey.learnedWords) as? [String: Int] ?? [:]
    }

    static func saveLearnedWords(_ words: [String: Int], storage: SharedClipboardStore.Storage = .live) {
        let url = fileURL(name: learnedWordsFileName, storage: storage)
        guard let data = try? JSONEncoder().encode(words) else { return }
        if (try? data.write(to: url, options: .atomic)) != nil,
           storage.settingsDefaults?.object(forKey: KeyboardPreferenceKey.learnedWords) != nil {
            storage.settingsDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedWords)
        }
    }

    static func learnedBigrams(storage: SharedClipboardStore.Storage = .live) -> [String: [String: Int]] {
        let url = fileURL(name: learnedBigramsFileName, storage: storage)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else { return [:] }
            return decoded
        }
        return storage.settingsDefaults?.dictionary(forKey: KeyboardPreferenceKey.learnedBigrams) as? [String: [String: Int]] ?? [:]
    }

    static func saveLearnedBigrams(_ bigrams: [String: [String: Int]], storage: SharedClipboardStore.Storage = .live) {
        let url = fileURL(name: learnedBigramsFileName, storage: storage)
        guard let data = try? JSONEncoder().encode(bigrams) else { return }
        if (try? data.write(to: url, options: .atomic)) != nil,
           storage.settingsDefaults?.object(forKey: KeyboardPreferenceKey.learnedBigrams) != nil {
            storage.settingsDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedBigrams)
        }
    }

    static func clearLearned(storage: SharedClipboardStore.Storage = .live) {
        try? FileManager.default.removeItem(at: fileURL(name: learnedWordsFileName, storage: storage))
        try? FileManager.default.removeItem(at: fileURL(name: learnedBigramsFileName, storage: storage))
        storage.settingsDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedWords)
        storage.settingsDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedBigrams)
    }

    /// Añade una palabra como conocida (no se autocorregirá).
    static func addWord(_ proposed: String) {
        let word = proposed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, !word.contains(" ") else { return }
        var words = learnedWords()
        words[word] = max(words[word] ?? 0, 5)
        saveLearnedWords(words)
    }

    static func removeWord(_ word: String) {
        var words = learnedWords()
        words.removeValue(forKey: word.lowercased())
        saveLearnedWords(words)

        var bigrams = learnedBigrams()
        bigrams.removeValue(forKey: word.lowercased())
        for key in bigrams.keys {
            bigrams[key]?.removeValue(forKey: word.lowercased())
        }
        saveLearnedBigrams(bigrams.filter { !$0.value.isEmpty })
    }

    static func shortcuts() -> [String: String] {
        defaults?.dictionary(forKey: KeyboardPreferenceKey.personalShortcuts) as? [String: String] ?? [:]
    }

    @discardableResult
    static func setShortcut(_ proposedShortcut: String, phrase proposedPhrase: String) -> Bool {
        let shortcut = proposedShortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let phrase = proposedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortcut.isEmpty, !shortcut.contains(" "), !phrase.isEmpty else { return false }
        var stored = shortcuts()
        stored[shortcut] = phrase
        defaults?.set(stored, forKey: KeyboardPreferenceKey.personalShortcuts)
        return true
    }

    static func removeShortcut(_ shortcut: String) {
        var stored = shortcuts()
        stored.removeValue(forKey: shortcut.lowercased())
        defaults?.set(stored, forKey: KeyboardPreferenceKey.personalShortcuts)
    }
}
