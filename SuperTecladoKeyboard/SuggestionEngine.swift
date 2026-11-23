import UIKit

#if SUPER_TECLADO_LOGIC_TESTS
@testable import SuperTeclado
#endif

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
    /// `true` en palabras nuevas que el usuario puede guardar con un toque («+ palabra»).
    var canAddToDictionary: Bool = false

    var id: String { "\(kind)-\(text)-\(canAddToDictionary)" }
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

/// La fábrica se invoca al precalentar en una pausa, nunca al pulsar espacio.
@MainActor
protocol SuggestionSpellValidating {
    func isValidSpelling(_ word: String, language: String) -> Bool
}

@MainActor
private final class SystemSuggestionSpellValidator: SuggestionSpellValidating {
    private let checker = UITextChecker()

    func isValidSpelling(_ word: String, language: String) -> Bool {
        if UITextChecker.hasLearnedWord(word.lowercased()) { return true }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: language
        )
        return misspelled.location == NSNotFound
    }
}

/// Copia de lo necesario para calcular sugerencias fuera del hilo principal, como hace Gboard:
/// así una palabra larga nunca retrasa la siguiente pulsación.
struct SuggestionSnapshot: Sendable {
    var dictionary: WordDictionary?
    var bigramModel: BigramModel? = nil
    var layout: LetterLayout
    var learned: [String: Int]
    var learnedBigrams: [String: [String: Int]] = [:]
    var preferredForms: [String: String] = [:]
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

    private func formatCandidate(_ candidate: String, to typed: String) -> String {
        if let preferred = preferredForms[candidate.lowercased()] {
            if typed.count > 1, typed == typed.uppercased(), typed != typed.lowercased() {
                return preferred.uppercased()
            }
            if typed.first?.isUppercase == true, preferred.first?.isUppercase != true {
                return preferred.prefix(1).uppercased() + preferred.dropFirst()
            }
            return preferred
        }
        return KeyboardTextLogic.matchCase(candidate, to: typed)
    }

    func compute(for word: String, previousWord: String? = nil, hints: CheckerHints? = nil) -> SuggestionResult {
        let lower = word.lowercased()
        let foldedLower = WordDictionary.fold(lower)
        let isKnown = isKnownWord(lower) || hints?.isKnown == true

        var others: [String] = []
        var seen: Set<String> = [lower]
        func append(_ candidate: String) {
            let key = candidate.lowercased()
            guard !candidate.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            others.append(formatCandidate(candidate, to: word))
        }

        // La corrección de erratas se calcula una sola vez y sirve para la corrección y la barra.
        var typos: [TypoCorrector.Candidate] = []
        if !isKnown, lower.count >= 3, let dictionary {
            typos = TypoCorrector.candidates(for: lower, in: dictionary, layout: layout, extraWords: learned, limit: 2)
        }

        var correction: String?
        var needsSpellCheck = false
        if !rejected.contains(lower),
           let shortcut = (personalShortcuts[lower] ?? lexiconShortcuts[lower]).map({ ShortcutVariables.expand($0) }) {
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
                correction = formatCandidate(best, to: word)
                seen.insert(best.lowercased())
            }
        }

        // 1. Completados contextuales según la palabra anterior (hábitos del usuario + bigramas):
        // p. ej. «por f» → «favor», «me g» → «gusta», «buenos d» → «días».
        if let previousWord, !previousWord.isEmpty {
            let prevLower = previousWord.lowercased()
            if let followers = learnedBigrams[prevLower] {
                followers
                    .filter { $0.value >= 1 && $0.key != lower && WordDictionary.fold($0.key).hasPrefix(foldedLower) }
                    .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                    .prefix(2)
                    .forEach { append($0.key) }
            }
            if let bigramModel {
                var baseMatches = bigramModel.followers(of: prevLower, matchingPrefix: lower, limit: 2)
                if baseMatches.isEmpty, let accentedPrev = dictionary?.bestForm(matching: prevLower), accentedPrev != prevLower {
                    baseMatches = bigramModel.followers(of: accentedPrev, matchingPrefix: lower, limit: 2)
                }
                baseMatches.forEach(append)
            }
        }

        // 2. Variantes con tilde de palabras existentes («esta» → «está», «que» → «qué», «si» → «sí»).
        if isKnown, correction == nil, let dictionary {
            dictionary.accentVariants(matching: lower).prefix(1).forEach(append)
        }

        // 3. Palabras aprendidas del usuario (sin exigir escribir la tilde para encontrarlas).
        learned
            .filter {
                $0.key != lower
                    && $0.value >= PersonalDictionary.knownThreshold
                    && WordDictionary.fold($0.key).hasPrefix(foldedLower)
            }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(2)
            .forEach { append($0.key) }

        // 4. Completados del diccionario, subiendo las palabras que el usuario ya suele escribir.
        if let dictionary {
            let candidates = dictionary.completions(for: word, limit: 8)
            let boosted = candidates.filter { (learned[$0] ?? 0) >= 1 }
                .sorted { (learned[$0] ?? 0) > (learned[$1] ?? 0) }
            boosted.forEach(append)
            candidates.forEach(append)
        } else if others.count < 2 {
            hints?.completions.prefix(3).forEach(append)
        }

        // 5. Segunda candidata de errata (si la primera ya pasó a `correction`, `seen` la omite).
        typos.forEach { append($0.word) }

        let canAdd = !isKnown && lower.count >= 2 && lower.contains(where: \.isLetter)
        let typed = SuggestionItem(text: word, kind: .typed, canAddToDictionary: canAdd)
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
    /// Crear el corrector y cargar su idioma puede bloquear. Solo se hace en una pausa.
    private let makeSpellValidator: @MainActor () -> any SuggestionSpellValidating
    private var spellValidator: (any SuggestionSpellValidating)?
    private var languageCode = "es_ES"
    private var resolvedLanguage: String?
    /// Si el corrector ya cargó el idioma actual.
    private var checkerWarm = false
    private var language: String {
        if let resolvedLanguage { return resolvedLanguage }
        let resolved = Self.checkerLanguage(for: languageCode)
        resolvedLanguage = resolved
        return resolved
    }
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
    private var preferredForms: [String: String] = [:]
    private var rejected: Set<String> = []
    private var pendingSave = false
    private var saveTask: Task<Void, Never>?
    /// Evita que una lectura asíncrona antigua del disco sobrescriba palabras recién aprendidas o añadidas.
    private var personalDataGeneration = 0
    /// Sugerencias ya calculadas por palabra y contexto; se vacía cuando cambia lo aprendido o el diccionario.
    private var cache: [String: SuggestionResult] = [:]
    /// Cambia al vaciar la caché, para descartar cálculos en segundo plano ya desfasados.
    private var cacheGeneration = 0

    convenience init() {
        self.init(makeSpellValidator: { SystemSuggestionSpellValidator() }, loadsPersonalData: true)
    }

    init(
        makeSpellValidator: @escaping @MainActor () -> any SuggestionSpellValidating,
        loadsPersonalData: Bool = false
    ) {
        self.makeSpellValidator = makeSpellValidator
        if loadsPersonalData { reloadPersonalData() }
    }

    /// Idioma del corrector de iOS (UITextChecker) más parecido al pedido.
    func setLanguage(_ code: String) {
        invalidateCache()
        if code != languageCode { checkerWarm = false }
        languageCode = code
        resolvedLanguage = nil
    }

    /// Hace una consulta de prueba al corrector para que cargue el idioma ahora (en una pausa)
    /// y no la primera vez que se autocorrige al pulsar espacio.
    @discardableResult
    func warmUpChecker() -> Bool {
        guard !checkerWarm, dictionary != nil else { return false }
        _ = isValidSpelling("hola")
        checkerWarm = true
        return true
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

    /// Lo aprendido se lee fuera del hilo principal (miles de palabras y pares): se hace cada vez
    /// que aparece el teclado y no debe retrasar el primer toque.
    func reloadPersonalData() {
        guard !pendingSave else { return }
        let generation = personalDataGeneration
        Task { [weak self] in
            let personal = await Task.detached(priority: .utility) {
                (
                    learned: PersonalDictionary.learnedWords(),
                    bigrams: PersonalDictionary.learnedBigrams(),
                    forms: PersonalDictionary.preferredForms(),
                    shortcuts: PersonalDictionary.shortcuts()
                )
            }.value
            // Si mientras tanto ha aprendido o añadido algo nuevo, lo de memoria es más reciente.
            guard let self, !self.pendingSave, self.personalDataGeneration == generation else { return }
            self.learned = personal.learned
            self.bigrams = personal.bigrams
            self.preferredForms = personal.forms
            self.personalShortcuts = personal.shortcuts
            self.invalidateCache()
        }
    }

    func clearCache() {
        invalidateCache()
    }

    private func invalidateCache() {
        cache.removeAll(keepingCapacity: true)
        cacheGeneration &+= 1
    }

    /// Palabras propias del usuario que también se pueden escribir deslizando.
    var glideExtraWords: [String: Int] {
        learned.filter { $0.value >= PersonalDictionary.knownThreshold && dictionary?.contains($0.key) != true }
    }

    private var snapshot: SuggestionSnapshot {
        SuggestionSnapshot(
            dictionary: dictionary,
            bigramModel: bigramModel,
            layout: layout,
            learned: learned,
            learnedBigrams: bigrams,
            preferredForms: preferredForms,
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

    private static func cacheKey(for word: String, previousWord: String?) -> String {
        guard let previousWord, !previousWord.isEmpty else { return word }
        return "\(previousWord.lowercased())|\(word)"
    }

    /// Sugerencias para la barra. Con el diccionario cargado se calculan en segundo plano.
    func result(for word: String, previousWord: String? = nil) async -> SuggestionResult {
        guard Self.isSuggestible(word) else { return .empty }
        let key = Self.cacheKey(for: word, previousWord: previousWord)
        if let cached = cache[key] { return cached }
        guard dictionary != nil else { return computeNow(for: word, previousWord: previousWord) }
        let snapshot = snapshot
        let generation = cacheGeneration
        let result = await Task.detached(priority: .userInitiated) {
            snapshot.compute(for: word, previousWord: previousWord)
        }.value
        // Para la barra no se consulta el corrector de iOS (va en el hilo principal y frena la
        // siguiente tecla); solo se hace si de verdad se va a corregir al pulsar espacio.
        if generation == cacheGeneration { store(result, forKey: key) }
        return result
    }

    /// Corrección que se aplica al pulsar espacio o un signo. Casi siempre ya está calculada.
    func autocorrection(for word: String, previousWord: String? = nil) -> String? {
        guard Self.isSuggestible(word) else { return nil }
        let key = Self.cacheKey(for: word, previousWord: previousWord)
        let result = cache[key] ?? computeNow(for: word, previousWord: previousWord)
        // Si se ha empezado a escribir sin ninguna pausa, la primera errata no debe crear ni
        // cargar UITextChecker desde la pulsación. Conservamos la propuesta para elegirla a mano.
        guard !result.needsSpellCheck || checkerWarm else { return nil }
        let checked = finalize(result, for: word, previousWord: previousWord)
        if checked.needsSpellCheck != result.needsSpellCheck || checked.autocorrection != result.autocorrection {
            store(checked, forKey: key)
        }
        return checked.autocorrection
    }

    /// Huecos de la barra con la fecha, la hora o el emoji que correspondan a la palabra.
    func slots(for result: SuggestionResult, word: String, includeEmoji: Bool) -> [SuggestionItem?] {
        // Antes de la primera pausa sigue siendo una sugerencia, no una autocorrección azul.
        var slots = result.needsSpellCheck && !checkerWarm ? result.slots.map { item in
            item.map { $0.kind == .correction ? SuggestionItem(text: $0.text, kind: .completion) : $0 }
        } : result.slots
        guard slots.count == 3 else { return slots }
        if let dateText = Self.dateSuggestion(for: word.lowercased()) {
            slots[2] = SuggestionItem(text: dateText, kind: .completion)
        } else if includeEmoji, let emoji = EmojiKeywords.emoji(for: result.autocorrection ?? word) {
            slots[2] = SuggestionItem(text: emoji, kind: .emoji)
        }
        return slots
    }

    private func computeNow(for word: String, previousWord: String? = nil) -> SuggestionResult {
        // Mientras carga el diccionario (medio segundo al abrir el teclado) no se sugiere nada:
        // el corrector de iOS tardaba en arrancar y congelaba las primeras teclas.
        guard dictionary != nil else { return .empty }
        let result = snapshot.compute(for: word, previousWord: previousWord)
        store(result, forKey: Self.cacheKey(for: word, previousWord: previousWord))
        return result
    }

    /// Solo se consulta el corrector de iOS (lento) cuando una palabra que no está en el
    /// diccionario se iba a corregir: si iOS la da por buena, se respeta.
    private func finalize(_ result: SuggestionResult, for word: String, previousWord: String? = nil) -> SuggestionResult {
        guard result.needsSpellCheck else { return result }
        if isValidSpelling(word) {
            return snapshot.compute(for: word, previousWord: previousWord, hints: SuggestionSnapshot.CheckerHints(isKnown: true))
        }
        var checked = result
        checked.needsSpellCheck = false
        return checked
    }

    private func store(_ result: SuggestionResult, forKey key: String) {
        if cache.count > 300 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
    }

    private func isValidSpelling(_ word: String) -> Bool {
        let validator: any SuggestionSpellValidating
        if let existing = spellValidator {
            validator = existing
        } else {
            let created = makeSpellValidator()
            spellValidator = created
            validator = created
        }
        return validator.isValidSpelling(word, language: language)
    }

    /// Siguiente palabra: base de frases reales combinada con lo que escribe el usuario.
    /// Sin palabra anterior (inicio de frase) propone las palabras con que suelen empezar.
    func predictions(after previous: String?, capitalized: Bool) -> [SuggestionItem?] {
        let base: [(word: String, count: Int)]
        var learnedFollowers: [String: Int] = [:]
        if let previous {
            let lower = previous.lowercased()
            var directBase = bigramModel?.followers(of: lower) ?? []
            if directBase.isEmpty, let accented = dictionary?.bestForm(matching: lower), accented != lower {
                directBase = bigramModel?.followers(of: accented) ?? []
            }
            base = directBase
            learnedFollowers = bigrams[lower] ?? [:]
            if let accented = dictionary?.bestForm(matching: lower), accented != lower,
               let accentedLearned = bigrams[accented] {
                for (word, count) in accentedLearned {
                    learnedFollowers[word, default: 0] += count
                }
            }
        } else {
            base = bigramModel?.sentenceStarters ?? []
        }
        let ranked = BigramModel.rank(base: base, learned: learnedFollowers).map { word in
            let displayed = PersonalDictionary.displayForm(for: word, preferredForms: preferredForms)
            let text: String
            if capitalized, displayed.first?.isUppercase != true {
                text = displayed.prefix(1).uppercased() + displayed.dropFirst()
            } else {
                text = displayed
            }
            return SuggestionItem(text: text, kind: .prediction)
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
        invalidateCache()
    }

    // MARK: Aprendizaje

    func learn(_ word: String) {
        invalidateCache()
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.count >= 2, lower.count <= 30, lower.contains(where: \.isLetter) else { return }
        personalDataGeneration &+= 1
        learned[lower, default: 0] += 1
        // Conservar mayúsculas internas intencionadas («WhatsApp», «iPhone», «SuperTeclado»).
        if trimmed.dropFirst().contains(where: \.isUppercase), trimmed != trimmed.uppercased() {
            preferredForms[lower] = trimmed
        }
        if learned.count > 3_000 {
            let removable = learned.sorted { $0.value < $1.value }.prefix(learned.count - 2_500)
            removable.forEach {
                learned.removeValue(forKey: $0.key)
                preferredForms.removeValue(forKey: $0.key)
            }
        }
        scheduleSave()
    }

    /// Añade explícitamente una palabra al diccionario personal del teclado («+ palabra» o ⚙️).
    @discardableResult
    func addWord(_ proposed: String, persist: Bool = true) -> String? {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.count >= 2, lower.count <= 30,
              !lower.contains(where: \.isWhitespace),
              lower.contains(where: \.isLetter) else { return nil }
        invalidateCache()
        personalDataGeneration &+= 1
        learned[lower] = max(learned[lower] ?? 0, 5)
        rejected.remove(lower)
        if trimmed != lower {
            preferredForms[lower] = trimmed
        }
        if persist {
            persistNow(synchronous: false)
        }
        return trimmed
    }

    /// Elimina una palabra aprendida (al mantener pulsada una sugerencia o desde ⚙️).
    @discardableResult
    func forget(_ word: String, persist: Bool = true) -> Bool {
        let lower = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        let existed = learned.removeValue(forKey: lower) != nil
            || preferredForms.removeValue(forKey: lower) != nil
            || rejected.remove(lower) != nil
        bigrams.removeValue(forKey: lower)
        for key in bigrams.keys {
            bigrams[key]?.removeValue(forKey: lower)
        }
        bigrams = bigrams.filter { !$0.value.isEmpty }
        guard existed else { return false }
        personalDataGeneration &+= 1
        invalidateCache()
        if persist {
            persistNow(synchronous: false)
        }
        return true
    }

    func isLearnedWord(_ word: String) -> Bool {
        (learned[word.lowercased()] ?? 0) >= PersonalDictionary.knownThreshold
    }

    func savedWordsList(limit: Int = 30) -> [String] {
        learned
            .filter { $0.value >= PersonalDictionary.knownThreshold }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { PersonalDictionary.displayForm(for: $0.key, preferredForms: preferredForms) }
    }

    func clearLearnedWords(persist: Bool = true) {
        saveTask?.cancel()
        saveTask = nil
        pendingSave = false
        personalDataGeneration &+= 1
        learned.removeAll()
        bigrams.removeAll()
        preferredForms.removeAll()
        rejected.removeAll()
        invalidateCache()
        if persist {
            Self.persistenceQueue.sync {
                PersonalDictionary.clearLearned()
            }
        }
    }

    func learnBigram(previous: String, word: String) {
        let first = previous.lowercased()
        let second = word.lowercased()
        guard first.contains(where: \.isLetter), second.contains(where: \.isLetter),
              first.count <= 30, second.count <= 30 else { return }
        personalDataGeneration &+= 1
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
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !lower.isEmpty else { return }
        rejected.insert(lower)
        guard persist else { return }
        // El diccionario propio conserva el rechazo sin arrancar el aprendizaje de iOS
        // desde la pulsación de borrar o de una sugerencia.
        personalDataGeneration &+= 1
        learned[lower, default: 0] += 2
        if trimmed != lower, trimmed.dropFirst().contains(where: \.isUppercase) {
            preferredForms[lower] = trimmed
        }
        scheduleSave()
    }

    /// Guarda de inmediato cualquier palabra o par pendiente al cerrar el teclado: iOS suele
    /// suspender la extensión antes de los 2 s del guardado diferido.
    func flushPendingSave() {
        guard pendingSave else { return }
        persistNow(synchronous: true)
    }

    private func scheduleSave() {
        guard !pendingSave else { return }
        pendingSave = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.persistNow(synchronous: false)
        }
    }

    private static let persistenceQueue = DispatchQueue(label: "com.spidy229.superteclado.dictionary.io", qos: .utility)

    private func persistNow(synchronous: Bool) {
        saveTask?.cancel()
        saveTask = nil
        pendingSave = false
        let learned = self.learned
        let bigrams = self.bigrams
        let forms = self.preferredForms
        if synchronous {
            Self.persistenceQueue.sync {
                PersonalDictionary.saveLearnedWords(learned)
                PersonalDictionary.saveLearnedBigrams(bigrams)
                PersonalDictionary.savePreferredForms(forms)
            }
        } else {
            Self.persistenceQueue.async {
                PersonalDictionary.saveLearnedWords(learned)
                PersonalDictionary.saveLearnedBigrams(bigrams)
                PersonalDictionary.savePreferredForms(forms)
            }
        }
    }
}
