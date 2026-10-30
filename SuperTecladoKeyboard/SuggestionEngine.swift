import UIKit

struct SuggestionItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case typed
        case correction
        case completion
    }

    let text: String
    let kind: Kind

    var id: String { "\(kind)-\(text)" }
}

struct SuggestionResult {
    /// Tres huecos (izquierda, centro, derecha) como en la barra de Gboard.
    var slots: [SuggestionItem?]
    var autocorrection: String?

    static let empty = SuggestionResult(slots: [], autocorrection: nil)
}

/// Sugerencias, autocorrección y aprendizaje de palabras basados en UITextChecker y en el
/// diccionario personal del usuario (sustituciones de texto y contactos de iOS).
@MainActor
final class SuggestionEngine {
    private let checker = UITextChecker()
    private let language: String
    private var shortcuts: [String: String] = [:]
    private var lexiconWords: Set<String> = []
    private var learned: [String: Int]
    private var rejected: Set<String> = []
    private var pendingLearnedSave = false

    init() {
        let available = UITextChecker.availableLanguages
        language = available.first { $0 == "es_ES" }
            ?? available.first { $0.hasPrefix("es") }
            ?? available.first
            ?? "es_ES"
        learned = (SharedClipboardStore.sharedDefaults?
            .dictionary(forKey: KeyboardPreferenceKey.learnedWords) as? [String: Int]) ?? [:]
    }

    func setLexicon(_ entries: [(input: String, replacement: String)]) {
        var shortcuts: [String: String] = [:]
        var words: Set<String> = []
        for entry in entries {
            let input = entry.input.lowercased()
            if input == entry.replacement.lowercased() {
                words.insert(input)
            } else {
                shortcuts[input] = entry.replacement
            }
        }
        self.shortcuts = shortcuts
        lexiconWords = words
    }

    func reloadLearnedWords() {
        learned = (SharedClipboardStore.sharedDefaults?
            .dictionary(forKey: KeyboardPreferenceKey.learnedWords) as? [String: Int]) ?? [:]
    }

    func suggestions(for word: String) -> SuggestionResult {
        guard !word.isEmpty, word.contains(where: \.isLetter), word.count <= 40 else { return .empty }
        let lower = word.lowercased()
        let range = NSRange(location: 0, length: (word as NSString).length)

        let isKnown = isKnownWord(lower, original: word, range: range)
        let completions = (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
            .filter { $0.lowercased() != lower }
        let guesses = isKnown ? [] : (checker.guesses(forWordRange: range, in: word, language: language) ?? [])
        let learnedMatches = learned
            .filter { $0.key.hasPrefix(lower) && $0.key != lower && $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        var others: [String] = []
        var seen: Set<String> = [lower]
        func append(_ candidate: String) {
            let key = candidate.lowercased()
            guard !candidate.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            others.append(KeyboardTextLogic.matchCase(candidate, to: word))
        }

        var correction: String?
        if let shortcut = shortcuts[lower] {
            correction = shortcut
            seen.insert(shortcut.lowercased())
        } else if !isKnown, !rejected.contains(lower) {
            correction = guesses.first { isPlausibleCorrection($0, for: word) }
                .map { KeyboardTextLogic.matchCase($0, to: word) }
            if let correction { seen.insert(correction.lowercased()) }
        }

        learnedMatches.forEach(append)
        completions.prefix(4).forEach(append)
        guesses.prefix(3).forEach(append)

        let typed = SuggestionItem(text: word, kind: .typed)
        let slots: [SuggestionItem?]
        if let correction {
            slots = [typed, SuggestionItem(text: correction, kind: .correction), others.first.map(completion)]
        } else if isKnown {
            slots = [others.first.map(completion), typed, others.dropFirst().first.map(completion)]
        } else {
            slots = [typed, others.first.map(completion), others.dropFirst().first.map(completion)]
        }
        return SuggestionResult(slots: slots, autocorrection: correction)
    }

    func learn(_ word: String) {
        let lower = word.lowercased()
        guard lower.count >= 2, lower.count <= 30, lower.contains(where: \.isLetter) else { return }
        learned[lower, default: 0] += 1
        if learned.count > 3_000 {
            let removable = learned.sorted { $0.value < $1.value }.prefix(learned.count - 2_500)
            removable.forEach { learned.removeValue(forKey: $0.key) }
        }
        scheduleSave()
    }

    /// El usuario deshizo una corrección o eligió lo que había escrito: se respeta su palabra.
    func reject(_ word: String) {
        let lower = word.lowercased()
        guard !lower.isEmpty else { return }
        rejected.insert(lower)
        UITextChecker.learnWord(lower)
        learned[lower, default: 0] += 2
        scheduleSave()
    }

    private func completion(_ text: String) -> SuggestionItem {
        SuggestionItem(text: text, kind: .completion)
    }

    private func isKnownWord(_ lower: String, original: String, range: NSRange) -> Bool {
        if lexiconWords.contains(lower) || rejected.contains(lower) { return true }
        if (learned[lower] ?? 0) >= 2 { return true }
        if UITextChecker.hasLearnedWord(lower) { return true }
        let misspelled = checker.rangeOfMisspelledWord(
            in: original,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        )
        return misspelled.location == NSNotFound
    }

    private func isPlausibleCorrection(_ guess: String, for word: String) -> Bool {
        guard word.count >= 2, !guess.contains(" ") else { return false }
        let foldedGuess = KeyboardTextLogic.folded(guess)
        let foldedWord = KeyboardTextLogic.folded(word)
        guard abs(foldedGuess.count - foldedWord.count) <= 2 else { return false }
        // Corregir solo tildes, o palabras que empiezan igual, evita cambios sorprendentes.
        return foldedGuess == foldedWord || foldedGuess.first == foldedWord.first
    }

    private func scheduleSave() {
        guard !pendingLearnedSave else { return }
        pendingLearnedSave = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            self.pendingLearnedSave = false
            SharedClipboardStore.sharedDefaults?.set(self.learned, forKey: KeyboardPreferenceKey.learnedWords)
        }
    }
}
