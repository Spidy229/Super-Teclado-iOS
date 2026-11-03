import UIKit

struct SuggestionItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case typed
        case correction
        case completion
        /// Siguiente palabra prevista tras un espacio.
        case prediction
        /// Alternativa a la palabra escrita deslizando.
        case glide
        case emoji
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

/// Sugerencias, autocorrección, predicción de la siguiente palabra y aprendizaje, a partir del
/// diccionario de frecuencias, UITextChecker y el diccionario personal del usuario.
@MainActor
final class SuggestionEngine {
    private let checker = UITextChecker()
    private var language: String
    /// Distribución activa, para saber qué teclas están al lado al corregir erratas.
    var layout: LetterLayout = .spanish
    private(set) var dictionary: WordDictionary?
    private var lexiconShortcuts: [String: String] = [:]
    private var lexiconWords: Set<String> = []
    private var personalShortcuts: [String: String] = [:]
    private var learned: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    private var rejected: Set<String> = []
    private var pendingSave = false

    /// Puntuación mínima (log de frecuencia ajustado por el tipo de errata) para autocorregir.
    private let typoThreshold = 8.0

    init() {
        language = Self.checkerLanguage(for: "es_ES")
        reloadPersonalData()
    }

    /// Idioma del corrector de iOS (UITextChecker) más parecido al pedido.
    func setLanguage(_ code: String) {
        language = Self.checkerLanguage(for: code)
    }

    private static func checkerLanguage(for code: String) -> String {
        let available = UITextChecker.availableLanguages
        let prefix = String(code.prefix(2))
        return available.first { $0 == code }
            ?? available.first { $0.hasPrefix(prefix) }
            ?? available.first
            ?? code
    }

    func setDictionary(_ dictionary: WordDictionary) {
        self.dictionary = dictionary
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
        lexiconShortcuts = shortcuts
        lexiconWords = words
    }

    func reloadPersonalData() {
        guard !pendingSave else { return }
        learned = PersonalDictionary.learnedWords()
        bigrams = PersonalDictionary.learnedBigrams()
        personalShortcuts = PersonalDictionary.shortcuts()
    }

    /// Palabras propias del usuario que también se pueden escribir deslizando.
    var glideExtraWords: [String: Int] {
        learned.filter { $0.value >= 3 && dictionary?.contains($0.key) != true }
    }

    // MARK: Sugerencias

    func suggestions(for word: String, includeEmoji: Bool) -> SuggestionResult {
        guard !word.isEmpty, word.contains(where: \.isLetter), word.count <= 40 else { return .empty }
        let lower = word.lowercased()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let isKnown = isKnownWord(lower, original: word, range: range)

        var others: [String] = []
        var seen: Set<String> = [lower]
        func append(_ candidate: String) {
            let key = candidate.lowercased()
            guard !candidate.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            others.append(KeyboardTextLogic.matchCase(candidate, to: word))
        }

        var correction: String?
        if let shortcut = personalShortcuts[lower] ?? lexiconShortcuts[lower] {
            correction = shortcut
            seen.insert(shortcut.lowercased())
        } else if !isKnown, !rejected.contains(lower), let best = bestCorrection(for: word, range: range) {
            correction = KeyboardTextLogic.matchCase(best, to: word)
            seen.insert(best.lowercased())
        }

        learned
            .filter { $0.key.hasPrefix(lower) && $0.key != lower && $0.value >= PersonalDictionary.knownThreshold }
            .sorted { $0.value > $1.value }
            .prefix(2)
            .forEach { append($0.key) }
        if let dictionary {
            dictionary.completions(for: word, limit: 4).forEach(append)
        }
        if others.count < 2 {
            (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
                .prefix(3)
                .forEach(append)
        }
        if !isKnown, correction == nil, let dictionary {
            TypoCorrector.candidates(for: lower, in: dictionary, layout: layout, limit: 2).forEach { append($0.word) }
        }

        let typed = SuggestionItem(text: word, kind: .typed)
        var slots: [SuggestionItem?]
        if let correction {
            slots = [typed, SuggestionItem(text: correction, kind: .correction), others.first.map(completion)]
        } else if isKnown {
            slots = [others.first.map(completion), typed, others.dropFirst().first.map(completion)]
        } else {
            slots = [typed, others.first.map(completion), others.dropFirst().first.map(completion)]
        }

        if includeEmoji, let emoji = EmojiKeywords.emoji(for: correction ?? word) {
            slots[2] = SuggestionItem(text: emoji, kind: .emoji)
        }
        return SuggestionResult(slots: slots, autocorrection: correction)
    }

    /// Siguiente palabra a partir de lo que el usuario suele escribir después de `previous`.
    func predictions(after previous: String) -> [SuggestionItem?] {
        guard let followers = bigrams[previous.lowercased()] else { return [] }
        let ranked = followers
            .filter { $0.value >= 2 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3)
            .map { SuggestionItem(text: $0.key, kind: .prediction) }
        guard !ranked.isEmpty else { return [] }
        return [ranked.dropFirst().first, ranked.first, ranked.dropFirst(2).first]
    }

    private func bestCorrection(for word: String, range: NSRange) -> String? {
        let lower = word.lowercased()
        if let dictionary {
            // Tildes y «ñ» olvidadas o mal puestas: «tambien» → «también», «manana» → «mañana».
            // Las palabras que ya están en el diccionario no llegan aquí («dé», «esta»…).
            if lower.count >= 2, let form = dictionary.bestForm(matching: lower), form != lower {
                return form
            }
            if lower.count >= 3,
               let candidate = TypoCorrector.candidates(for: lower, in: dictionary, layout: layout, limit: 1).first,
               candidate.score >= typoThreshold {
                return candidate.word
            }
        }
        let guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        let plausible = guesses.filter { isPlausibleCorrection($0, for: word) }
        if let dictionary {
            return plausible.max { (dictionary.count(of: $0) ?? 0) < (dictionary.count(of: $1) ?? 0) }
        }
        return plausible.first
    }

    // MARK: Aprendizaje

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

    func learnBigram(previous: String, word: String) {
        let first = previous.lowercased()
        let second = word.lowercased()
        guard first.contains(where: \.isLetter), second.contains(where: \.isLetter),
              first.count <= 30, second.count <= 30 else { return }
        var followers = bigrams[first] ?? [:]
        followers[second, default: 0] += 1
        if followers.count > 12 {
            followers.sorted { $0.value < $1.value }.prefix(followers.count - 10).forEach {
                followers.removeValue(forKey: $0.key)
            }
        }
        bigrams[first] = followers
        if bigrams.count > 2_000 {
            let removable = bigrams
                .sorted { $0.value.values.reduce(0, +) < $1.value.values.reduce(0, +) }
                .prefix(bigrams.count - 1_600)
            removable.forEach { bigrams.removeValue(forKey: $0.key) }
        }
        scheduleSave()
    }

    /// El usuario deshizo una corrección o eligió lo que había escrito: se respeta su palabra.
    func reject(_ word: String, persist: Bool = true) {
        let lower = word.lowercased()
        guard !lower.isEmpty else { return }
        rejected.insert(lower)
        guard persist else { return }
        UITextChecker.learnWord(lower)
        learned[lower, default: 0] += 2
        scheduleSave()
    }

    private func completion(_ text: String) -> SuggestionItem {
        SuggestionItem(text: text, kind: .completion)
    }

    private func isKnownWord(_ lower: String, original: String, range: NSRange) -> Bool {
        if lexiconWords.contains(lower) || rejected.contains(lower) { return true }
        if (learned[lower] ?? 0) >= PersonalDictionary.knownThreshold { return true }
        if dictionary?.contains(lower) == true { return true }
        if UITextChecker.hasLearnedWord(lower) { return true }
        // Si ya hay diccionario, una palabra que no está en él y tiene una forma con tilde
        // muy usada se trata como errata aunque UITextChecker la acepte.
        if let dictionary, dictionary.bestForm(matching: lower) != nil { return false }
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
        guard !pendingSave else { return }
        pendingSave = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            self.pendingSave = false
            PersonalDictionary.saveLearnedWords(self.learned)
            PersonalDictionary.saveLearnedBigrams(self.bigrams)
        }
    }
}
