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

struct SuggestionResult: Sendable {
    /// Tres huecos (izquierda, centro, derecha) como en la barra de Gboard.
    var slots: [SuggestionItem?]
    var autocorrection: String?
    /// La corrección sale de una errata probable en una palabra que no está en el diccionario:
    /// antes de usarla se confirma con el corrector de iOS (que solo funciona en el hilo principal).
    var needsSpellCheck = false

    static let empty = SuggestionResult(slots: [], autocorrection: nil)
}

/// Copia de lo necesario para calcular sugerencias fuera del hilo principal, como hace Gboard:
/// así una palabra larga nunca retrasa la siguiente pulsación.
struct SuggestionSnapshot: Sendable {
    var dictionary: WordDictionary?
    var layout: LetterLayout
    var learned: [String: Int]
    var lexiconShortcuts: [String: String]
    var lexiconWords: Set<String>
    var personalShortcuts: [String: String]
    var rejected: Set<String>

    /// Sin diccionario, el corrector de iOS aporta estos datos desde el hilo principal.
    struct CheckerHints: Sendable {
        var isKnown = false
        var completions: [String] = []
        var guesses: [String] = []
    }

    /// Puntuación mínima (log de frecuencia ajustado por el tipo de errata) para autocorregir.
    static let typoThreshold = 8.0

    func isKnownWord(_ lower: String) -> Bool {
        lexiconWords.contains(lower)
            || rejected.contains(lower)
            || (learned[lower] ?? 0) >= PersonalDictionary.knownThreshold
            || dictionary?.contains(lower) == true
    }

    func compute(for word: String, hints: CheckerHints? = nil) -> SuggestionResult {
        let lower = word.lowercased()
        let isKnown = isKnownWord(lower) || hints?.isKnown == true

        var others: [String] = []
        var seen: Set<String> = [lower]
        func append(_ candidate: String) {
            let key = candidate.lowercased()
            guard !candidate.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            others.append(KeyboardTextLogic.matchCase(candidate, to: word))
        }

        // La corrección de erratas se calcula una sola vez y sirve para la corrección y la barra.
        var typos: [TypoCorrector.Candidate] = []
        if !isKnown, lower.count >= 3, let dictionary {
            typos = TypoCorrector.candidates(for: lower, in: dictionary, layout: layout, limit: 2)
        }

        var correction: String?
        var needsSpellCheck = false
        if let shortcut = (personalShortcuts[lower] ?? lexiconShortcuts[lower]).map({ ShortcutVariables.expand($0) }) {
            correction = shortcut
            seen.insert(shortcut.lowercased())
        } else if !isKnown, !rejected.contains(lower) {
            var best: String?
            if let dictionary {
                // Tildes y «ñ» olvidadas o mal puestas: «tambien» → «también», «manana» → «mañana».
                // Las palabras que ya están en el diccionario no llegan aquí («dé», «esta»…).
                if lower.count >= 2, let form = dictionary.bestForm(matching: lower), form != lower {
                    best = form
                } else if let candidate = typos.first, candidate.score >= Self.typoThreshold {
                    best = candidate.word
                    needsSpellCheck = true
                }
            } else {
                best = hints?.guesses.first { Self.isPlausibleCorrection($0, for: word) }
            }
            if let best {
                correction = KeyboardTextLogic.matchCase(best, to: word)
                seen.insert(best.lowercased())
            }
        }

        learned
            .filter { $0.key.hasPrefix(lower) && $0.key != lower && $0.value >= PersonalDictionary.knownThreshold }
            .sorted { $0.value > $1.value }
            .prefix(2)
            .forEach { append($0.key) }
        if let dictionary {
            dictionary.completions(for: word, limit: 4).forEach(append)
        } else if others.count < 2 {
            hints?.completions.prefix(3).forEach(append)
        }
        if correction == nil {
            typos.forEach { append($0.word) }
        }

        let typed = SuggestionItem(text: word, kind: .typed)
        func completion(_ text: String) -> SuggestionItem { SuggestionItem(text: text, kind: .completion) }
        let slots: [SuggestionItem?]
        if let correction {
            slots = [typed, SuggestionItem(text: correction, kind: .correction), others.first.map(completion)]
        } else if isKnown {
            slots = [others.first.map(completion), typed, others.dropFirst().first.map(completion)]
        } else {
            slots = [typed, others.first.map(completion), others.dropFirst().first.map(completion)]
        }
        return SuggestionResult(slots: slots, autocorrection: correction, needsSpellCheck: needsSpellCheck)
    }

    static func isPlausibleCorrection(_ guess: String, for word: String) -> Bool {
        guard word.count >= 2, !guess.contains(" ") else { return false }
        let foldedGuess = KeyboardTextLogic.folded(guess)
        let foldedWord = KeyboardTextLogic.folded(word)
        guard abs(foldedGuess.count - foldedWord.count) <= 2 else { return false }
        // Corregir solo tildes, o palabras que empiezan igual, evita cambios sorprendentes.
        return foldedGuess == foldedWord || foldedGuess.first == foldedWord.first
    }
}

/// Sugerencias, autocorrección, predicción de la siguiente palabra y aprendizaje, a partir del
/// diccionario de frecuencias, UITextChecker y el diccionario personal del usuario.
@MainActor
final class SuggestionEngine {
    private let checker = UITextChecker()
    private var language: String
    /// Distribución activa, para saber qué teclas están al lado al corregir erratas.
    var layout: LetterLayout = .spanish {
        didSet { if layout != oldValue { invalidateCache() } }
    }
    private(set) var dictionary: WordDictionary?
    private var bigramModel: BigramModel?
    private var lexiconShortcuts: [String: String] = [:]
    private var lexiconWords: Set<String> = []
    private var personalShortcuts: [String: String] = [:]
    private var learned: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    private var rejected: Set<String> = []
    private var pendingSave = false
    /// Sugerencias ya calculadas por palabra; se vacía cuando cambia lo aprendido o el diccionario.
    private var cache: [String: SuggestionResult] = [:]
    /// Cambia al vaciar la caché, para descartar cálculos en segundo plano ya desfasados.
    private var cacheGeneration = 0

    init() {
        language = Self.checkerLanguage(for: "es_ES")
        reloadPersonalData()
    }

    /// Idioma del corrector de iOS (UITextChecker) más parecido al pedido.
    func setLanguage(_ code: String) {
        invalidateCache()
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
        invalidateCache()
    }

    func setLexicon(_ entries: [(input: String, replacement: String)]) {
        invalidateCache()
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
        invalidateCache()
        guard !pendingSave else { return }
        learned = PersonalDictionary.learnedWords()
        bigrams = PersonalDictionary.learnedBigrams()
        personalShortcuts = PersonalDictionary.shortcuts()
    }

    private func invalidateCache() {
        cache.removeAll(keepingCapacity: true)
        cacheGeneration &+= 1
    }

    /// Palabras propias del usuario que también se pueden escribir deslizando.
    var glideExtraWords: [String: Int] {
        learned.filter { $0.value >= 3 && dictionary?.contains($0.key) != true }
    }

    private var snapshot: SuggestionSnapshot {
        SuggestionSnapshot(
            dictionary: dictionary,
            layout: layout,
            learned: learned,
            lexiconShortcuts: lexiconShortcuts,
            lexiconWords: lexiconWords,
            personalShortcuts: personalShortcuts,
            rejected: rejected
        )
    }

    // MARK: Sugerencias

    private static func isSuggestible(_ word: String) -> Bool {
        !word.isEmpty && word.count <= 40 && word.contains(where: \.isLetter)
    }

    /// Sugerencias para la barra. Con el diccionario cargado se calculan en segundo plano.
    func result(for word: String) async -> SuggestionResult {
        guard Self.isSuggestible(word) else { return .empty }
        if let cached = cache[word] { return cached }
        guard dictionary != nil else { return computeNow(for: word) }
        let snapshot = snapshot
        let generation = cacheGeneration
        let computed = await Task.detached(priority: .userInitiated) {
            snapshot.compute(for: word)
        }.value
        let result = finalize(computed, for: word)
        if generation == cacheGeneration { store(result, for: word) }
        return result
    }

    /// Corrección que se aplica al pulsar espacio o un signo. Casi siempre ya está calculada.
    func autocorrection(for word: String) -> String? {
        guard Self.isSuggestible(word) else { return nil }
        return (cache[word] ?? computeNow(for: word)).autocorrection
    }

    /// Huecos de la barra con la fecha, la hora o el emoji que correspondan a la palabra.
    func slots(for result: SuggestionResult, word: String, includeEmoji: Bool) -> [SuggestionItem?] {
        var slots = result.slots
        guard slots.count == 3 else { return slots }
        if let dateText = Self.dateSuggestion(for: word.lowercased()) {
            slots[2] = SuggestionItem(text: dateText, kind: .completion)
        } else if includeEmoji, let emoji = EmojiKeywords.emoji(for: result.autocorrection ?? word) {
            slots[2] = SuggestionItem(text: emoji, kind: .emoji)
        }
        return slots
    }

    private func computeNow(for word: String) -> SuggestionResult {
        let hints = dictionary == nil ? checkerHints(for: word) : nil
        let result = finalize(snapshot.compute(for: word, hints: hints), for: word)
        store(result, for: word)
        return result
    }

    /// Solo se consulta el corrector de iOS (lento) cuando una palabra que no está en el
    /// diccionario se iba a corregir: si iOS la da por buena, se respeta.
    private func finalize(_ result: SuggestionResult, for word: String) -> SuggestionResult {
        guard result.needsSpellCheck else { return result }
        if isValidSpelling(word) {
            return snapshot.compute(for: word, hints: SuggestionSnapshot.CheckerHints(isKnown: true))
        }
        var checked = result
        checked.needsSpellCheck = false
        return checked
    }

    private func store(_ result: SuggestionResult, for word: String) {
        if cache.count > 300 { cache.removeAll(keepingCapacity: true) }
        cache[word] = result
    }

    private func isValidSpelling(_ word: String) -> Bool {
        if UITextChecker.hasLearnedWord(word.lowercased()) { return true }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        )
        return misspelled.location == NSNotFound
    }

    /// Mientras no ha cargado el diccionario se usa el corrector de iOS.
    private func checkerHints(for word: String) -> SuggestionSnapshot.CheckerHints {
        let range = NSRange(location: 0, length: (word as NSString).length)
        var hints = SuggestionSnapshot.CheckerHints()
        hints.isKnown = isValidSpelling(word)
        hints.completions = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        if !hints.isKnown {
            hints.guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        }
        return hints
    }

    /// Siguiente palabra: base de frases reales combinada con lo que escribe el usuario.
    /// Sin palabra anterior (inicio de frase) propone las palabras con que suelen empezar.
    func predictions(after previous: String?, capitalized: Bool) -> [SuggestionItem?] {
        let base = previous.map { bigramModel?.followers(of: $0) ?? [] } ?? (bigramModel?.sentenceStarters ?? [])
        let learnedFollowers = previous.flatMap { bigrams[$0.lowercased()] } ?? [:]
        let ranked = BigramModel.rank(base: base, learned: learnedFollowers).map { word in
            SuggestionItem(text: capitalized ? word.prefix(1).uppercased() + word.dropFirst() : word, kind: .prediction)
        }
        guard !ranked.isEmpty else { return [] }
        return [ranked.dropFirst().first, ranked.first, ranked.dropFirst(2).first]
    }

    private static let todayWords: Set<String> = ["hoy", "fecha", "avui", "hoje", "today", "date", "oggi", "heute"]
    private static let nowWords: Set<String> = ["ahora", "hora", "ara", "agora", "now", "time", "adesso", "jetzt"]

    /// Al escribir «hoy» o «ahora», la barra ofrece la fecha o la hora actuales.
    private static func dateSuggestion(for word: String) -> String? {
        if todayWords.contains(word) { return ShortcutVariables.expand("{fecha}") }
        if nowWords.contains(word) { return ShortcutVariables.expand("{hora}") }
        return nil
    }

    func setBigramModel(_ model: BigramModel?) {
        bigramModel = model
    }

    // MARK: Aprendizaje

    func learn(_ word: String) {
        invalidateCache()
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
        invalidateCache()
        let lower = word.lowercased()
        guard !lower.isEmpty else { return }
        rejected.insert(lower)
        guard persist else { return }
        UITextChecker.learnWord(lower)
        learned[lower, default: 0] += 2
        scheduleSave()
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
