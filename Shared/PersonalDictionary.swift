import Foundation

/// Diccionario personal compartido entre la app y el teclado: palabras aprendidas, pares de
/// palabras para predecir la siguiente y atajos («qtal» → «¿Qué tal?»).
enum PersonalDictionary {
    /// Veces que debe aparecer una palabra para que se considere correcta.
    static let knownThreshold = 2

    private static var defaults: UserDefaults? { SharedClipboardStore.sharedDefaults }

    static func learnedWords() -> [String: Int] {
        defaults?.dictionary(forKey: KeyboardPreferenceKey.learnedWords) as? [String: Int] ?? [:]
    }

    static func saveLearnedWords(_ words: [String: Int]) {
        defaults?.set(words, forKey: KeyboardPreferenceKey.learnedWords)
    }

    static func learnedBigrams() -> [String: [String: Int]] {
        defaults?.dictionary(forKey: KeyboardPreferenceKey.learnedBigrams) as? [String: [String: Int]] ?? [:]
    }

    static func saveLearnedBigrams(_ bigrams: [String: [String: Int]]) {
        defaults?.set(bigrams, forKey: KeyboardPreferenceKey.learnedBigrams)
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
