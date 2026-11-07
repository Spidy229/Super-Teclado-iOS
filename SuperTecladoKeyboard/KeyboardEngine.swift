import AudioToolbox
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum KeyFeedbackKind {
    case character
    case delete
    case modifier
}

/// Recuento de lo que pasa con cada toque, para averiguar en el propio móvil por qué falla
/// alguno (se ve en el engranaje ⚙︎ de la barra).
struct TouchDiagnostics {
    var touches = 0
    /// Por qué camino llegó primero cada dedo (el reconocedor de gestos o la vista).
    var viaRecognizer = 0
    var viaView = 0
    var typed = 0
    /// Teclas escritas porque tocó otro dedo antes de levantar el anterior.
    var rollovers = 0
    /// Toques que iOS canceló: los cortos se escriben igual, los demás se pierden.
    var cancelledTyped = 0
    var cancelledLost = 0
    /// Dedos de los que iOS no avisó al levantarse.
    var unfinished = 0
    var ignored = 0
    var glides = 0
    var glidesAsTaps = 0
    var cursorSwipes = 0
    var alternates = 0
    /// Toques entre dos letras resueltos con el diccionario.
    var smartChoices = 0
    /// Últimos toques, del más reciente al más antiguo.
    var recent: [String] = []
    /// Milisegundos desde que el dedo toca hasta que el teclado recibe el toque.
    private(set) var delivery: [Double] = []
    /// Milisegundos que tarda el teclado en atender cada toque.
    private(set) var handling: [Double] = []
    /// Milisegundos que tarda iOS en aceptar cada vibración.
    private(set) var feedback: [Double] = []
    /// Vibraciones y clics que se saltaron para no acumular retraso al teclear deprisa.
    var skippedHaptics = 0
    var skippedSounds = 0
    /// Veces que el teclado estuvo bloqueado más de 100 ms, y el bloqueo más largo.
    private(set) var stalls = 0
    private(set) var longestStall: Double = 0
    /// Retraso de cada aviso del temporizador de control (cada 0,1 s), en milisegundos.
    private(set) var lateness: [Double] = []

    mutating func log(_ entry: String) {
        recent.insert(entry, at: 0)
        if recent.count > 12 { recent.removeLast(recent.count - 12) }
    }

    mutating func recordDelivery(_ seconds: Double) {
        Self.append(seconds * 1000, to: &delivery)
    }

    mutating func recordHandling(_ seconds: Double) {
        Self.append(seconds * 1000, to: &handling)
    }

    mutating func recordFeedback(_ seconds: Double) {
        Self.append(seconds * 1000, to: &feedback)
    }

    /// Retraso con que llega el temporizador de control: si pasa de 100 ms, el teclado estuvo
    /// bloqueado ese tiempo.
    mutating func recordMainThreadDelay(_ seconds: Double) {
        let milliseconds = seconds * 1000
        Self.append(max(0, milliseconds), to: &lateness)
        guard milliseconds > 0 else { return }
        if milliseconds > 100 { stalls += 1 }
        longestStall = max(longestStall, milliseconds)
    }

    private static func append(_ value: Double, to samples: inout [Double]) {
        guard value.isFinite, value >= 0 else { return }
        samples.append(value)
        if samples.count > 80 { samples.removeFirst(samples.count - 80) }
    }

    static func summary(_ samples: [Double]) -> String {
        guard !samples.isEmpty else { return "—" }
        let average = samples.reduce(0, +) / Double(samples.count)
        return String(format: "media %.0f ms · máx %.0f ms", average, samples.max() ?? 0)
    }
}

/// Lo que cambia con cada pulsación (sugerencias, pegado rápido) va aparte del motor: así solo
/// se vuelve a dibujar la barra de sugerencias y no todo el teclado.
@MainActor
final class SuggestionBarState: ObservableObject {
    @Published var suggestions: [SuggestionItem?] = []
    @Published var showsToolbar = false
    @Published var quickPaste: KeyboardClip?
}

/// Estado y lógica del teclado. Las vistas SwiftUI solo leen este objeto y le envían acciones.
@MainActor
final class KeyboardEngine: ObservableObject {
    weak var controller: KeyboardViewController?

    @Published var panel: KeyboardPanel = .typing
    @Published var page: KeyboardPage = .letters
    @Published var shift: ShiftState = .off
    @Published var savedClips: [KeyboardClip] = []
    @Published var recentClips: [KeyboardClip] = []
    @Published var folders: [String] = []
    @Published var clipboardEnabled = true
    @Published var isEditingClips = false
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var hasFullAccess = false
    @Published var needsInputModeSwitchKey = true
    @Published var returnKeyType: UIReturnKeyType = .default
    @Published var keyboardType: UIKeyboardType = .default
    @Published var isDark = true
    @Published var preferences = KeyboardPreferences()
    @Published var metrics = KeyboardMetrics.make(isPad: false, isLandscape: false, numberRow: false)
    @Published var toast: String?
    @Published var recentEmojis: [String] = []
    @Published private(set) var isGliding = false
    @Published private(set) var backgroundImage: UIImage?
    @Published private(set) var searchQuery = ""
    @Published private(set) var emojiSearchResults: [String] = []
    @Published private(set) var emojiTones: [String: String] = [:]
    @Published private(set) var clipSearchResults: [KeyboardClip] = []
    @Published private(set) var toastActionTitle: String?

    let glideTrail = GlideTrail()
    let bar = SuggestionBarState()

    var suggestions: [SuggestionItem?] {
        get { bar.suggestions }
        set { bar.suggestions = newValue }
    }

    var showsToolbar: Bool {
        get { bar.showsToolbar }
        set { bar.showsToolbar = newValue }
    }

    var quickPaste: KeyboardClip? {
        get { bar.quickPaste }
        set { bar.quickPaste = newValue }
    }

    /// Última pulsación de una tecla (para no consultar el portapapeles mientras se escribe).
    private(set) var lastKeyTouch: TimeInterval = 0
    var touchDiagnostics = TouchDiagnostics()
    /// Letras que el propio teclado acaba de escribir en la palabra actual. Al teclear muy
    /// deprisa el contexto del documento puede ir una letra por detrás.
    private var typedWord = ""

    /// Cambio del portapapeles hecho por el propio teclado (para no volver a capturarlo).
    var ownPasteboardChangeCount: Int?
    /// Tras varios cierres seguidos: sin diccionarios, contactos ni foto de fondo.
    var safeMode = false

    private let suggestionEngine = SuggestionEngine()
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    private var feedbackGeneratorStyle: HapticStyleOption?
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    private var pendingAutocorrection: (original: String, replacement: String, suffix: String)?
    private var quickPasteDate = Date.distantPast
    private var traitStyle: UIUserInterfaceStyle = .unspecified
    private var toastTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var toastAction: (() -> Void)?
    /// Último borrado del portapapeles, para poder deshacerlo durante unos segundos.
    private var undoDeletion: (saved: [SharedClipboardClip], temporary: [SharedTemporaryClip])?
    private var undoTask: Task<Void, Never>?
    private var glidePoints: [CGPoint] = []
    private var glideTarget: GlideTarget?
    private var lastGlidePreview = Date.distantPast
    private var glidePreviewTask: Task<Void, Never>?
    /// Última palabra escrita deslizando y sus alternativas, para cambiarla desde la barra.
    private var lastGlide: (word: String, alternatives: [String])?
    /// Espacio añadido automáticamente tras elegir una sugerencia (se quita ante un signo).
    private var autoSpaceInserted = false
    /// Idiomas del diccionario cargado, p. ej. «es+en» (`nil` mientras no se ha cargado ninguno).
    private var loadedLanguages: String?
    private var backgroundDate: Date?
    private var emojiIndex: EmojiSearchIndex?
    private var emojiIndexLoadStarted = false
    private static let recentEmojisKey = "super-teclado-recent-emojis"
    private static let emojiTonesKey = "super-teclado-emoji-tones"
    private static let searchableEmojis = EmojiCatalog.categories.flatMap(\.emojis)

    init() {
        recentEmojis = UserDefaults.standard.stringArray(forKey: Self.recentEmojisKey) ?? []
        emojiTones = UserDefaults.standard.dictionary(forKey: Self.emojiTonesKey) as? [String: String] ?? [:]
    }

    private var proxy: (any UITextDocumentProxy)? { controller?.textDocumentProxy }

    var currentWord: String {
        KeyboardTextLogic.currentWord(before: proxy?.documentContextBeforeInput)
    }

    var isWebField: Bool { keyboardType == .URL || keyboardType == .webSearch }

    var isEmailField: Bool { keyboardType == .emailAddress }

    /// En las búsquedas, las teclas escriben en el buscador y no en el documento.
    var isSearching: Bool { panel == .emojiSearch || panel == .clipboardSearch }

    /// Modo incógnito elegido por el usuario o campo sensible (contraseñas, códigos, tarjetas).
    var isIncognito: Bool {
        if preferences.incognito { return true }
        let contentType: UITextContentType? = proxy?.textContentType ?? nil
        guard let contentType else { return false }
        return [.password, .newPassword, .oneTimeCode, .creditCardNumber].contains(contentType)
    }

    var spaceBarTitle: String {
        if preferences.incognito { return "Incógnito" }
        let primary = preferences.primaryLanguage.nativeName
        return preferences.secondaryLanguage.map { "\(primary) · \($0.nativeName)" } ?? primary
    }

    var letterLayout: LetterLayout { preferences.letterLayout }

    var dictionary: WordDictionary? { suggestionEngine.dictionary }

    /// Palabra que se está escribiendo, en minúsculas, para elegir la tecla más probable.
    var wordForPrediction: String {
        let context = currentWord.lowercased()
        return typedWord.count > context.count && typedWord.hasPrefix(context) ? typedWord : context
    }

    /// La precisión inteligente no se usa donde se escriben cosas que no son palabras.
    var smartTouchAllowed: Bool {
        guard preferences.smartTouch, panel == .typing, page == .letters,
              !isWebField, !isEmailField, suggestionEngine.dictionary != nil else { return false }
        guard proxy?.autocorrectionType != .no else { return false }
        let contentType: UITextContentType? = proxy?.textContentType ?? nil
        guard let contentType else { return true }
        let free: [UITextContentType] = [.password, .newPassword, .oneTimeCode, .creditCardNumber, .username, .emailAddress, .URL]
        return !free.contains(contentType)
    }

    // MARK: Contexto

    func loadPreferences() {
        let loaded = KeyboardPreferences.load()
        if loaded != preferences { preferences = loaded }
        suggestionEngine.reloadPersonalData()
        updateAppearance()
        guard !safeMode else {
            backgroundImage = nil
            return
        }
        loadDictionaryIfNeeded()
        loadBackgroundIfNeeded()
    }

    /// Carga la foto del tema «Mi foto» solo cuando se usa y cuando ha cambiado.
    private func loadBackgroundIfNeeded() {
        guard preferences.theme == .photo else {
            if backgroundImage != nil { backgroundImage = nil }
            backgroundDate = nil
            return
        }
        let date = KeyboardBackgroundStore.modificationDate
        guard date != backgroundDate || backgroundImage == nil else { return }
        backgroundDate = date
        backgroundImage = KeyboardBackgroundStore.load(maxPixelSize: 1_400)
    }

    func refreshContext() {
        guard let proxy else { return }
        let newReturnKey = proxy.returnKeyType ?? .default
        if newReturnKey != returnKeyType { returnKeyType = newReturnKey }
        let newType = proxy.keyboardType ?? .default
        if newType != keyboardType {
            keyboardType = newType
            page = Self.defaultPage(for: newType)
        }
        updateAppearance()
        // Si el cursor se ha ido a otra palabra, lo escrito antes ya no cuenta.
        if !typedWord.hasPrefix(currentWord.lowercased()) { typedWord = "" }
        updateShiftState()
        scheduleSuggestions()
    }

    func setTraitStyle(_ style: UIUserInterfaceStyle) {
        guard style != traitStyle else { return }
        traitStyle = style
        updateAppearance()
    }

    func updateAppearance() {
        let dark: Bool
        if preferences.theme == .custom {
            dark = preferences.customColors.isDark
        } else if let fixed = preferences.theme.isDark {
            dark = fixed
        } else {
            switch proxy?.keyboardAppearance ?? .default {
            case .dark: dark = true
            case .light: dark = false
            default: dark = traitStyle == .dark
            }
        }
        if dark != isDark { isDark = dark }
    }

    func setLexicon(_ entries: [(input: String, replacement: String)]) {
        suggestionEngine.setLexicon(entries)
    }

    /// Carga el diccionario de frecuencias en segundo plano, y otra vez si cambian los idiomas.
    private func loadDictionaryIfNeeded() {
        let primary = preferences.primaryLanguage
        let secondary = preferences.secondaryLanguage
        let languages = "\(primary.rawValue)+\(secondary?.rawValue ?? "")"
        suggestionEngine.layout = letterLayout
        guard loadedLanguages != languages,
              let url = Bundle.main.url(forResource: primary.dictionaryResource, withExtension: "txt") else { return }
        loadedLanguages = languages
        suggestionEngine.setLanguage(primary.spellCheckerLanguage)
        let secondaryURL = secondary.flatMap { Bundle.main.url(forResource: $0.dictionaryResource, withExtension: "txt") }
        let bigramsURL = Bundle.main.url(forResource: "bigrams-\(primary.rawValue)", withExtension: "txt")
        let started = Date()
        Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                (
                    dictionary: WordDictionary.load(from: url, secondary: secondaryURL, secondaryWeight: 0.6),
                    bigrams: bigramsURL.flatMap(BigramModel.load(from:))
                )
            }.value
            guard let self, let dictionary = loaded.dictionary, self.loadedLanguages == languages else { return }
            self.suggestionEngine.setDictionary(dictionary)
            self.suggestionEngine.setBigramModel(loaded.bigrams)
            self.scheduleSuggestions()
            if self.hasFullAccess {
                KeyboardDiagnostics.recordDictionary(
                    milliseconds: Int(Date().timeIntervalSince(started) * 1000),
                    wordCount: dictionary.words.count,
                    languages: languages
                )
                KeyboardViewController.recordAvailableMemory()
            }
        }
    }

    /// Restablece la página al empezar a escribir en otro campo, como Gboard.
    func prepareForNewField() {
        typedWord = ""
        page = Self.defaultPage(for: proxy?.keyboardType ?? keyboardType)
        lastGlide = nil
        autoSpaceInserted = false
        pendingAutocorrection = nil
    }

    private static func defaultPage(for type: UIKeyboardType) -> KeyboardPage {
        switch type {
        case .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad: .numberPad
        case .numbersAndPunctuation: .numbers
        default: .letters
        }
    }

    private var autocapitalizationMode: AutoCapitalizationMode {
        guard preferences.autocapitalize, !isWebField, !isEmailField else { return .none }
        switch proxy?.autocapitalizationType ?? .sentences {
        case .none: return .none
        case .words: return .words
        case .allCharacters: return .allCharacters
        default: return .sentences
        }
    }

    private var suggestionsAllowed: Bool {
        guard preferences.suggestions, !isWebField, !isEmailField else { return false }
        return page != .numberPad
    }

    private var autocorrectAllowed: Bool {
        guard preferences.autocorrect, suggestionsAllowed else { return false }
        return proxy?.autocorrectionType != .no
    }

    private func updateShiftState() {
        if isSearching {
            if shift != .off { shift = .off }
            return
        }
        guard shift != .locked else { return }
        let capitalize = KeyboardTextLogic.shouldCapitalize(
            context: proxy?.documentContextBeforeInput,
            mode: autocapitalizationMode
        )
        let newState: ShiftState = capitalize ? .on : .off
        if newState != shift { shift = newState }
    }

    private func refreshSuggestions() async {
        let word = currentWord
        if let glide = lastGlide, glide.word != word { lastGlide = nil }

        let newSuggestions: [SuggestionItem?]
        if let glide = lastGlide, glide.alternatives.count > 1 {
            let others = glide.alternatives.filter { $0 != glide.word }
                .map { SuggestionItem(text: $0, kind: .glide) }
            newSuggestions = [others.first, SuggestionItem(text: glide.word, kind: .typed), others.dropFirst().first]
        } else if !suggestionsAllowed {
            newSuggestions = []
        } else if word.isEmpty {
            newSuggestions = predictions()
        } else {
            // Con el diccionario cargado se calculan en segundo plano, como en Gboard.
            let result = await suggestionEngine.result(for: word)
            guard !Task.isCancelled, currentWord == word else { return }
            let slots = suggestionEngine.slots(for: result, word: word, includeEmoji: preferences.emojiSuggestions)
            // En azul solo lo que se va a corregir al pulsar espacio: sin autocorrección, la
            // propuesta se muestra como una sugerencia normal.
            newSuggestions = autocorrectAllowed ? slots : slots.map { item in
                item.map { $0.kind == .correction ? SuggestionItem(text: $0.text, kind: .completion) : $0 }
            }
        }
        if newSuggestions != suggestions { suggestions = newSuggestions }
        if quickPaste != nil, Date().timeIntervalSince(quickPasteDate) > 180 { quickPaste = nil }
    }

    private func predictions() -> [SuggestionItem?] {
        guard preferences.nextWordPrediction,
              let context = proxy?.documentContextBeforeInput, context.hasSuffix(" ") else { return [] }
        let capitalized = shift != .off
        if let previous = KeyboardTextLogic.previousWord(before: context) {
            return suggestionEngine.predictions(after: previous, capitalized: capitalized)
        }
        // Tras un punto: palabras con las que suele empezar una frase.
        guard !context.trimmingCharacters(in: .whitespaces).isEmpty,
              KeyboardTextLogic.isSentenceStart(context) else { return [] }
        return suggestionEngine.predictions(after: nil, capitalized: true)
    }

    /// Aprende la palabra y el par «palabra anterior → palabra» para predecir.
    private func recordWord(_ word: String, context: String?) {
        guard suggestionsAllowed, !isIncognito, !word.isEmpty else { return }
        suggestionEngine.learn(word)
        if preferences.nextWordPrediction, let previous = KeyboardTextLogic.previousWord(before: context) {
            suggestionEngine.learnBigram(previous: previous, word: word)
        }
    }

    private func afterEdit(keepingTypedWord: Bool = false) {
        if !keepingTypedWord { typedWord = "" }
        updateShiftState()
        scheduleSuggestions()
    }

    /// Las sugerencias se calculan justo después de escribir, sin bloquear la pulsación: al
    /// teclear rápido solo se calculan para la última letra.
    private func scheduleSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(12))
            guard !Task.isCancelled, let self else { return }
            await self.refreshSuggestions()
        }
    }

    // MARK: Escritura

    func displayText(for value: String, caseSensitive: Bool) -> String {
        guard caseSensitive, page == .letters, shift != .off else { return value }
        return value.uppercased()
    }

    func insertCharacter(_ value: String, caseSensitive: Bool) {
        if isSearching {
            setSearchQuery(searchQuery + value.lowercased())
            return
        }
        guard let proxy else { return }
        let output = displayText(for: value, caseSensitive: caseSensitive)
        if showsToolbar { showsToolbar = false }
        let isPunctuation = [".", ",", "?", "!", ";", ":"].contains(output)
        if isPunctuation, autoSpaceInserted, proxy.documentContextBeforeInput?.hasSuffix(" ") == true {
            // «hola ,» → «hola, »: el signo se pega a la palabra elegida en la barra.
            proxy.deleteBackward()
            proxy.insertText(output + " ")
            autoSpaceInserted = false
            pendingAutocorrection = nil
            if shift == .on { shift = .off }
            afterEdit()
            return
        }
        autoSpaceInserted = false
        if isPunctuation, !currentWord.isEmpty {
            commitWord(separator: output)
        } else {
            proxy.insertText(output)
            pendingAutocorrection = nil
        }
        if shift == .on { shift = .off }
        let continuesWord = output.count == 1 && (output.first?.isLetter == true || output == "'")
        if continuesWord { typedWord += output.lowercased() }
        afterEdit(keepingTypedWord: continuesWord)
    }

    func insertSpace() {
        if isSearching {
            if !searchQuery.isEmpty, !searchQuery.hasSuffix(" ") {
                setSearchQuery(searchQuery + " ")
            }
            return
        }
        guard let proxy else { return }
        let now = Date()
        if autoSpaceInserted, proxy.documentContextBeforeInput?.hasSuffix(" ") == true {
            // La sugerencia ya dejó el espacio: pulsar espacio justo después no lo duplica (otro
            // espacio seguido sí pone el punto, como siempre).
            autoSpaceInserted = false
            lastSpaceTap = now
            afterEdit()
            return
        }
        autoSpaceInserted = false
        if preferences.doubleSpacePeriod,
           now.timeIntervalSince(lastSpaceTap) < 0.5,
           KeyboardTextLogic.shouldConvertDoubleSpace(context: proxy.documentContextBeforeInput) {
            proxy.deleteBackward()
            proxy.insertText(". ")
            pendingAutocorrection = nil
            lastSpaceTap = .distantPast
        } else {
            commitWord(separator: " ")
            lastSpaceTap = now
        }
        afterEdit()
    }

    func insertReturn() {
        if panel == .emojiSearch {
            if let first = emojiSearchResults.first { insertSearchedEmoji(first) }
            return
        }
        if panel == .clipboardSearch {
            if let first = clipSearchResults.first { useClip(first) }
            return
        }
        autoSpaceInserted = false
        proxy?.insertText("\n")
        pendingAutocorrection = nil
        afterEdit()
    }

    private func commitWord(separator: String) {
        guard let proxy else { return }
        let word = currentWord
        let context = proxy.documentContextBeforeInput
        if !word.isEmpty,
           autocorrectAllowed,
           let correction = suggestionEngine.autocorrection(for: word),
           correction != word {
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(correction + separator)
            pendingAutocorrection = (word, correction, separator)
            recordWord(correction, context: context)
        } else {
            proxy.insertText(separator)
            pendingAutocorrection = nil
            recordWord(word, context: context)
        }
    }

    func deleteBackward() {
        if isSearching {
            setSearchQuery(String(searchQuery.dropLast()))
            return
        }
        guard let proxy else { return }
        autoSpaceInserted = false
        if let glide = lastGlide, proxy.documentContextBeforeInput?.hasSuffix(glide.word) == true {
            // Igual que Gboard: borrar justo después de deslizar elimina la palabra entera.
            for _ in 0..<glide.word.count { proxy.deleteBackward() }
            lastGlide = nil
            pendingAutocorrection = nil
            afterEdit()
            return
        }
        if let pending = pendingAutocorrection,
           let context = proxy.documentContextBeforeInput,
           context.hasSuffix(pending.replacement + pending.suffix) {
            // Igual que Gboard: borrar justo después de una corrección la deshace.
            for _ in 0..<(pending.replacement.count + pending.suffix.count) { proxy.deleteBackward() }
            proxy.insertText(pending.original)
            suggestionEngine.reject(pending.original, persist: !isIncognito)
        } else {
            proxy.deleteBackward()
            if !typedWord.isEmpty {
                typedWord.removeLast()
                pendingAutocorrection = nil
                afterEdit(keepingTypedWord: true)
                return
            }
        }
        pendingAutocorrection = nil
        afterEdit()
    }

    func deleteWordBackward() {
        if isSearching {
            let count = KeyboardTextLogic.wordDeletionLength(context: searchQuery)
            setSearchQuery(String(searchQuery.dropLast(max(count, 1))))
            return
        }
        guard let proxy else { return }
        let count = max(1, KeyboardTextLogic.wordDeletionLength(context: proxy.documentContextBeforeInput))
        for _ in 0..<count { proxy.deleteBackward() }
        pendingAutocorrection = nil
        afterEdit()
    }

    func tapShift() {
        let now = Date()
        switch shift {
        case .locked:
            shift = .off
        case .on:
            shift = now.timeIntervalSince(lastShiftTap) < 0.35 ? .locked : .off
        case .off:
            shift = .on
        }
        lastShiftTap = now
    }

    func selectSuggestion(_ item: SuggestionItem) {
        guard let proxy else { return }
        let word = currentWord
        let context = proxy.documentContextBeforeInput
        // Lo que hay detrás del cursor se mira antes de escribir nada.
        let textAfterCursor = proxy.documentContextAfterInput
        pendingAutocorrection = nil
        lastSpaceTap = .distantPast

        switch item.kind {
        case .glide:
            // Sustituye la palabra deslizada por la alternativa elegida.
            guard let glide = lastGlide, context?.hasSuffix(glide.word) == true else { return }
            for _ in 0..<glide.word.count { proxy.deleteBackward() }
            proxy.insertText(item.text)
            lastGlide = (item.text, glide.alternatives)
        case .emoji:
            proxy.insertText(word.isEmpty ? item.text : " " + item.text)
            recordWord(word, context: context)
            rememberEmoji(item.text)
            lastGlide = nil
            addSpaceAfterSuggestion(textAfterCursor: textAfterCursor)
        case .prediction:
            proxy.insertText(item.text)
            recordWord(item.text, context: context)
            addSpaceAfterSuggestion(textAfterCursor: textAfterCursor)
        case .typed, .correction, .completion:
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(item.text)
            if item.kind == .typed { suggestionEngine.reject(item.text, persist: !isIncognito) }
            recordWord(item.text, context: context)
            lastGlide = nil
            addSpaceAfterSuggestion(textAfterCursor: textAfterCursor)
        }
        if shift == .on { shift = .off }
        afterEdit()
    }

    /// Espacio tras la palabra elegida, como en Gboard, pero sin duplicar uno que ya esté detrás
    /// del cursor (entonces el cursor salta detrás de él) ni ponerlo delante de un signo. Se
    /// puede desactivar en el engranaje ⚙︎.
    private func addSpaceAfterSuggestion(textAfterCursor: String?) {
        guard preferences.spaceAfterSuggestion, let proxy else {
            autoSpaceInserted = false
            return
        }
        switch KeyboardTextLogic.suggestionSpace(before: textAfterCursor) {
        case .insert:
            proxy.insertText(" ")
            autoSpaceInserted = true
        case .skipExisting:
            proxy.adjustTextPosition(byCharacterOffset: 1)
            autoSpaceInserted = true
        case .none:
            autoSpaceInserted = false
        }
    }

    // MARK: Escritura deslizando

    var canGlide: Bool {
        preferences.glideTyping && panel == .typing && page == .letters
            && !isWebField && !isEmailField && suggestionEngine.dictionary != nil
    }

    func beginGlide(at point: CGPoint, target: GlideTarget) {
        glidePoints = [point]
        glideTarget = target
        lastGlidePreview = .distantPast
        isGliding = true
        glideTrail.preview = nil
    }

    func extendGlide(to point: CGPoint) {
        guard isGliding, let last = glidePoints.last, GlideDecoder.distance(last, point) >= 2 else { return }
        glidePoints.append(point)
        updateGlidePreview()
    }

    /// Muestra en la barra la palabra que se va reconociendo mientras se desliza, como Gboard.
    private func updateGlidePreview() {
        guard glidePreviewTask == nil, glidePoints.count >= 6,
              Date().timeIntervalSince(lastGlidePreview) > 0.12,
              let target = glideTarget, let dictionary = suggestionEngine.dictionary else { return }
        lastGlidePreview = Date()
        let path = glidePoints
        let decoder = GlideDecoder(keyCenters: target.centers, keyWidth: target.keyWidth)
        glidePreviewTask = Task { [weak self] in
            let best = await Task.detached(priority: .userInitiated) {
                decoder.decode(path: path, dictionary: dictionary, limit: 1).first
            }.value
            guard let self else { return }
            self.glidePreviewTask = nil
            guard self.isGliding else { return }
            self.glideTrail.preview = best.map { self.applyShift($0) }
        }
    }

    /// Devuelve `false` si el trazo fue tan corto que debe tratarse como una pulsación normal.
    @discardableResult
    func endGlide() -> Bool {
        guard isGliding else { return true }
        isGliding = false
        glidePreviewTask?.cancel()
        glidePreviewTask = nil
        glideTrail.preview = nil
        let path = glidePoints
        glidePoints = []
        guard let target = glideTarget else { return false }
        guard GlideDecoder.length(of: path) >= Double(target.keyWidth) * 0.9 else { return false }
        guard let proxy, let dictionary = suggestionEngine.dictionary else { return true }

        let decoder = GlideDecoder(keyCenters: target.centers, keyWidth: target.keyWidth)
        let candidates = decoder.decode(
            path: path,
            dictionary: dictionary,
            extraWords: suggestionEngine.glideExtraWords,
            limit: 4
        )
        guard !candidates.isEmpty else {
            // Un trazo corto sin palabra era una pulsación rápida que resbaló: se escribe la
            // letra en vez de perderla.
            if GlideDecoder.length(of: path) < Double(target.keyWidth) * 2.5 { return false }
            keyFeedback(.modifier)
            return true
        }

        let styled = candidates.map { applyShift($0) }
        if let last = proxy.documentContextBeforeInput?.last,
           !last.isWhitespace, !["¿", "¡", "(", "\"", "«", "@", "#", "/"].contains(last) {
            proxy.insertText(" ")
        }
        proxy.insertText(styled[0])
        pendingAutocorrection = nil
        autoSpaceInserted = false
        if showsToolbar { showsToolbar = false }
        lastGlide = (styled[0], styled)
        if shift == .on { shift = .off }
        afterEdit()
        return true
    }

    /// El sistema canceló el toque (p. ej. un gesto de la pantalla): no se escribe nada.
    func cancelGlide() {
        guard isGliding else { return }
        isGliding = false
        glidePreviewTask?.cancel()
        glidePreviewTask = nil
        glideTrail.preview = nil
        glidePoints = []
    }

    private func applyShift(_ word: String) -> String {
        switch shift {
        case .locked: word.uppercased()
        case .on: word.prefix(1).uppercased() + word.dropFirst()
        case .off: word
        }
    }

    func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        proxy?.adjustTextPosition(byCharacterOffset: offset)
        pendingAutocorrection = nil
        autoSpaceInserted = false
        afterEdit()
    }

    func moveCursorWordLeft() {
        moveCursor(by: -KeyboardTextLogic.wordDeletionLength(context: proxy?.documentContextBeforeInput))
    }

    func moveCursorWordRight() {
        moveCursor(by: KeyboardTextLogic.nextWordOffset(after: proxy?.documentContextAfterInput))
    }

    func moveCursorToLineStart() {
        moveCursor(by: -KeyboardTextLogic.offsetToLineStart(before: proxy?.documentContextBeforeInput))
    }

    func moveCursorToLineEnd() {
        moveCursor(by: KeyboardTextLogic.offsetToLineEnd(after: proxy?.documentContextAfterInput))
    }

    func setPage(_ newPage: KeyboardPage) {
        page = newPage
        if newPage == .letters { updateShiftState() }
    }

    func insertEmoji(_ emoji: String) {
        proxy?.insertText(emoji)
        pendingAutocorrection = nil
        autoSpaceInserted = false
        rememberEmoji(emoji)
        afterEdit()
    }

    /// Inserta un elemento de la fila de favoritos (emoji o símbolo).
    func insertFavorite(_ item: String) {
        proxy?.insertText(item)
        pendingAutocorrection = nil
        autoSpaceInserted = false
        if item.unicodeScalars.contains(where: { $0.value >= 0x2190 }) { rememberEmoji(item) }
        afterEdit()
    }

    private func rememberEmoji(_ emoji: String) {
        guard !isIncognito else { return }
        var recents = recentEmojis.filter { $0 != emoji }
        recents.insert(emoji, at: 0)
        recentEmojis = Array(recents.prefix(32))
        UserDefaults.standard.set(recentEmojis, forKey: Self.recentEmojisKey)
    }

    func advanceToNextInputMode() {
        controller?.advanceToNextInputMode()
    }

    func dismissKeyboard() {
        controller?.dismissKeyboard()
    }

    // MARK: Paneles y barra de herramientas

    func open(_ newPanel: KeyboardPanel) {
        if newPanel == .clipboard { controller?.checkPasteboard(); reloadClips() }
        isEditingClips = false
        selectedClipIDs = []
        panel = newPanel
    }

    func closePanel() {
        isEditingClips = false
        selectedClipIDs = []
        panel = .typing
        afterEdit()
    }

    /// Cambia ajustes desde el panel del teclado y los guarda. Funciona aunque la firma no
    /// comparta el App Group con la app.
    func updatePreferences(_ change: (inout KeyboardPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        let layoutChanged = updated.numberRow != preferences.numberRow
            || updated.height != preferences.height
            || updated.favoritesRow != preferences.favoritesRow
        preferences = updated
        updated.save()
        updateAppearance()
        if !safeMode { loadDictionaryIfNeeded() }
        if layoutChanged { controller?.view.setNeedsLayout() }
    }

    /// Informe de los toques y de cómo está configurado el teclado, para pegarlo en un mensaje.
    func diagnosticsReport() -> String {
        let diagnostics = touchDiagnostics
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        let memory = Double(os_proc_available_memory()) / 1_048_576
        func on(_ value: Bool) -> String { value ? "sí" : "no" }
        var lines = [
            "Super Teclado \(version) · \(model) · iOS \(UIDevice.current.systemVersion)",
            "Retraso de iOS al entregar el toque: \(TouchDiagnostics.summary(diagnostics.delivery))",
            "Tiempo del teclado por toque: \(TouchDiagnostics.summary(diagnostics.handling))",
            String(format: "Bloqueos de más de 100 ms: %d (el mayor %.0f ms)", diagnostics.stalls, diagnostics.longestStall),
            "Retraso del hilo principal: \(TouchDiagnostics.summary(diagnostics.lateness))",
            "Vibración (lo que tarda iOS en aceptarla): \(TouchDiagnostics.summary(diagnostics.feedback)) · saltadas \(diagnostics.skippedHaptics) · clics saltados \(diagnostics.skippedSounds)",
            String(format: "Memoria libre: %.0f MB", memory),
            "Toques \(diagnostics.touches) (por reconocedor \(diagnostics.viaRecognizer), por la vista \(diagnostics.viaView)) · escritos \(diagnostics.typed) · con otro dedo \(diagnostics.rollovers)",
            "Cancelados por iOS: escritos \(diagnostics.cancelledTyped), perdidos \(diagnostics.cancelledLost) · sin aviso de fin \(diagnostics.unfinished) · ignorados \(diagnostics.ignored)",
            "Deslizamientos \(diagnostics.glides) (eran toques \(diagnostics.glidesAsTaps)) · cursor \(diagnostics.cursorSwipes) · pulsación larga \(diagnostics.alternates) · precisión \(diagnostics.smartChoices)",
            "Vibración \(on(preferences.haptics && hasFullAccess)) (\(preferences.hapticsStyle.rawValue), \(Int(preferences.hapticsStrength * 100)) %) · sonido \(on(preferences.sound)) · ventana al pulsar \(on(preferences.keyPopups))",
            "Escritura deslizando \(on(preferences.glideTyping)) · precisión inteligente \(on(preferences.smartTouch)) · autocorrección \(on(preferences.autocorrect)) · tema \(preferences.theme.rawValue)",
            "Acceso total \(on(hasFullAccess)) · App Group \(on(SharedClipboardStore.isAppGroupAvailable))"
        ]
        if !diagnostics.recent.isEmpty {
            lines.append("Últimos toques: " + diagnostics.recent.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    /// Copia el informe para pegarlo en un mensaje (no se guarda en el historial del teclado).
    func copyDiagnosticsReport() {
        guard requireFullAccess() else { return }
        UIPasteboard.general.string = diagnosticsReport()
        ownPasteboardChangeCount = UIPasteboard.general.changeCount
        showToast("Informe copiado: pégalo en tu mensaje")
    }

    /// Deja el motor de vibración listo antes del primer toque.
    func prepareFeedback() {
        guard preferences.haptics, hasFullAccess else { return }
        hapticGenerator().prepare()
    }

    /// Vibración de prueba con el tipo e intensidad elegidos.
    func previewHaptic() {
        keyFeedback(.character)
    }

    func setTheme(_ theme: KeyboardThemeOption) {
        preferences.theme = theme
        KeyboardPreferences.setTheme(theme)
        updateAppearance()
        loadBackgroundIfNeeded()
    }

    /// Transparencia del tema «Cristal». Mientras se arrastra el control solo se redibuja; se
    /// guarda al soltarlo.
    func setGlassTransparency(_ value: Double, persist: Bool) {
        let clamped = min(max(value, 0), 1)
        if preferences.glassTransparency != clamped { preferences.glassTransparency = clamped }
        if persist {
            SharedClipboardStore.sharedDefaults?.set(clamped, forKey: KeyboardPreferenceKey.glassTransparency)
        }
    }

    func setKeyBorders(_ enabled: Bool) {
        preferences.keyBorders = enabled
        KeyboardPreferences.setKeyBorders(enabled)
    }

    func toggleIncognito() {
        preferences.incognito.toggle()
        KeyboardPreferences.setIncognito(preferences.incognito)
        showToast(preferences.incognito
            ? "Modo incógnito: no se aprenden palabras ni se guarda lo copiado"
            : "Modo incógnito desactivado")
    }

    // MARK: Emojis

    func openEmojiSearch() {
        loadEmojiIndexIfNeeded()
        searchQuery = ""
        updateEmojiSearchResults()
        page = .letters
        shift = .off
        panel = .emojiSearch
    }

    func insertSearchedEmoji(_ emoji: String) {
        keyFeedback(.character)
        insertEmoji(preferredVariant(of: emoji))
    }

    func preferredVariant(of emoji: String) -> String {
        emojiTones[EmojiSkinTone.baseKey(emoji)] ?? emoji
    }

    func setPreferredVariant(_ variant: String, for emoji: String) {
        emojiTones[EmojiSkinTone.baseKey(emoji)] = variant
        UserDefaults.standard.set(emojiTones, forKey: Self.emojiTonesKey)
    }

    private func setSearchQuery(_ query: String) {
        searchQuery = query
        if panel == .clipboardSearch {
            updateClipSearchResults()
        } else {
            updateEmojiSearchResults()
        }
    }

    private func updateEmojiSearchResults() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            var seen = Set<String>()
            emojiSearchResults = (recentEmojis + EmojiSkinTone.popular)
                .filter { seen.insert(EmojiSkinTone.baseKey($0)).inserted }
        } else {
            emojiSearchResults = emojiIndex?.search(query, in: Self.searchableEmojis) ?? []
        }
    }

    private func loadEmojiIndexIfNeeded() {
        guard !emojiIndexLoadStarted,
              let url = Bundle.main.url(forResource: "es-emojis", withExtension: "txt") else { return }
        emojiIndexLoadStarted = true
        Task { [weak self] in
            let index = await Task.detached(priority: .userInitiated) {
                EmojiSearchIndex.load(from: url)
            }.value
            guard let self, let index else { return }
            self.emojiIndex = index
            self.updateEmojiSearchResults()
        }
    }

    func setOneHandedMode(_ mode: OneHandedMode) {
        preferences.oneHandedMode = mode
        KeyboardPreferences.setOneHandedMode(mode)
    }

    func toggleOneHandedMode() {
        setOneHandedMode(preferences.oneHandedMode == .off ? .right : .off)
    }

    // MARK: Portapapeles

    func reloadClips() {
        applyClips(
            saved: SharedClipboardStore.load(),
            recent: SharedClipboardStore.loadTemporaryInbox(),
            folders: SharedClipboardStore.loadFolders(),
            enabled: SharedClipboardStore.automaticCaptureEnabled
        )
    }

    /// Igual que `reloadClips`, pero leyendo el historial fuera del hilo principal. Lo usan las
    /// comprobaciones automáticas del portapapeles, que no deben frenar nunca el teclado.
    func reloadClipsInBackground(offerQuickPaste offer: Bool = false) {
        Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                (
                    saved: SharedClipboardStore.load(),
                    recent: SharedClipboardStore.loadTemporaryInbox(),
                    folders: SharedClipboardStore.loadFolders(),
                    enabled: SharedClipboardStore.automaticCaptureEnabled
                )
            }.value
            guard let self else { return }
            self.applyClips(saved: loaded.saved, recent: loaded.recent, folders: loaded.folders, enabled: loaded.enabled)
            if offer { self.offerQuickPaste() }
        }
    }

    private func applyClips(saved: [SharedClipboardClip], recent: [SharedTemporaryClip], folders loadedFolders: [String], enabled: Bool) {
        let savedClips = saved.map(KeyboardClip.init(saved:))
        let recentClips = recent.map(KeyboardClip.init(recent:))
        if savedClips != self.savedClips { self.savedClips = savedClips }
        if recentClips != self.recentClips { self.recentClips = recentClips }
        if loadedFolders != folders { folders = loadedFolders }
        if enabled != clipboardEnabled { clipboardEnabled = enabled }
        let kept = selectedClipIDs.filter { id in
            savedClips.contains { $0.id == id } || recentClips.contains { $0.id == id }
        }
        // Sin cambios no se avisa a SwiftUI (redibujaría todo el teclado).
        if kept != selectedClipIDs { selectedClipIDs = kept }
    }

    /// Muestra lo último copiado en la barra de sugerencias, como el pegado rápido de Gboard.
    func offerQuickPaste() {
        guard preferences.quickPaste, let clip = recentClips.first else { return }
        quickPaste = clip
        quickPasteDate = Date()
    }

    func useQuickPaste() {
        guard let clip = quickPaste else { return }
        quickPaste = nil
        useClip(clip)
    }

    func useClip(_ clip: KeyboardClip, transform: ClipboardClassifier.Transform? = nil) {
        if clip.isImage {
            copyClip(clip)
            return
        }
        proxy?.insertText(transform?.apply(to: clip.text) ?? clip.text)
        pendingAutocorrection = nil
        if hasFullAccess {
            switch clip.source {
            case .saved: SharedClipboardStore.markUsed(id: clip.id)
            case .recent: SharedClipboardStore.markTemporaryUsed(id: clip.id)
            }
            reloadClips()
        }
        afterEdit()
    }

    func copyClip(_ clip: KeyboardClip) {
        guard requireFullAccess() else { return }
        if let fileName = clip.imageFileName {
            guard let data = SharedClipboardStore.imageData(fileName: fileName) else {
                showToast("No se encontró la imagen")
                return
            }
            UIPasteboard.general.setData(data, forPasteboardType: UTType.jpeg.identifier)
            ownPasteboardChangeCount = UIPasteboard.general.changeCount
            showToast("Imagen copiada · mantén pulsado el campo y elige Pegar")
        } else {
            UIPasteboard.general.string = clip.text
            ownPasteboardChangeCount = UIPasteboard.general.changeCount
            showToast("Copiado")
        }
    }

    func togglePin(_ clip: KeyboardClip) {
        guard requireFullAccess() else { return }
        switch clip.source {
        case .recent:
            SharedClipboardStore.promoteTemporary(id: clip.id)
            showToast("Fijado")
        case .saved:
            SharedClipboardStore.demoteSaved(id: clip.id)
            showToast("Movido a Recientes")
        }
        reloadClips()
    }

    func deleteClips(_ clips: [KeyboardClip]) {
        guard requireFullAccess(), !clips.isEmpty else { return }
        finishPendingUndo()
        // Las imágenes se borran del disco cuando ya no se puede deshacer.
        let saved = SharedClipboardStore.deleteSaved(
            ids: Set(clips.filter(\.isSaved).map(\.id)),
            removeImages: false
        )
        let temporary = SharedClipboardStore.deleteTemporary(
            ids: Set(clips.filter { !$0.isSaved }.map(\.id)),
            removeImages: false
        )
        undoDeletion = (saved, temporary)
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.finishPendingUndo()
        }
        if let quickPaste, clips.contains(where: { $0.id == quickPaste.id }) { self.quickPaste = nil }
        reloadClips()
        if panel == .clipboardSearch { updateClipSearchResults() }
        showToast(
            clips.count == 1 ? "Eliminado" : "\(clips.count) elementos eliminados",
            actionTitle: "Deshacer"
        ) { [weak self] in
            self?.undoLastDeletion()
        }
    }

    private func undoLastDeletion() {
        guard let deletion = undoDeletion else { return }
        undoTask?.cancel()
        undoDeletion = nil
        SharedClipboardStore.restore(saved: deletion.saved, temporary: deletion.temporary)
        reloadClips()
        if panel == .clipboardSearch { updateClipSearchResults() }
        showToast("Restaurado")
    }

    /// Borra del disco las imágenes del último borrado si ya no se puede deshacer.
    private func finishPendingUndo() {
        undoTask?.cancel()
        undoTask = nil
        guard let deletion = undoDeletion else { return }
        undoDeletion = nil
        let files = deletion.saved.compactMap(\.imageFileName) + deletion.temporary.compactMap(\.imageFileName)
        files.forEach(SharedClipboardStore.removeImage(fileName:))
    }

    /// Pega varios elementos seguidos, cada uno en su línea (las imágenes se omiten).
    func pasteClips(_ clips: [KeyboardClip]) {
        let texts = clips.filter { !$0.isImage }.map(\.text)
        guard !texts.isEmpty else {
            showToast("Las imágenes se pegan una a una desde el campo")
            return
        }
        proxy?.insertText(texts.joined(separator: "\n"))
        pendingAutocorrection = nil
        afterEdit()
        showToast(texts.count == 1 ? "Pegado" : "\(texts.count) elementos pegados")
    }

    /// Copia varios elementos juntos al portapapeles del sistema.
    func copyClips(_ clips: [KeyboardClip]) {
        guard requireFullAccess() else { return }
        let texts = clips.filter { !$0.isImage }.map(\.text)
        guard !texts.isEmpty else { return }
        UIPasteboard.general.string = texts.joined(separator: "\n")
        ownPasteboardChangeCount = UIPasteboard.general.changeCount
        showToast(texts.count == 1 ? "Copiado" : "\(texts.count) elementos copiados juntos")
    }

    func moveClip(_ clip: KeyboardClip, toFolder folder: String?) {
        guard requireFullAccess() else { return }
        if !clip.isSaved { SharedClipboardStore.promoteTemporary(id: clip.id) }
        SharedClipboardStore.setFolder(folder, forSavedID: clip.id)
        reloadClips()
        showToast(folder.map { "Movido a «\($0)»" } ?? "Quitado de la carpeta")
    }

    // MARK: Búsqueda en el portapapeles

    func openClipboardSearch() {
        reloadClips()
        searchQuery = ""
        page = .letters
        shift = .off
        isEditingClips = false
        panel = .clipboardSearch
        updateClipSearchResults()
    }

    private func updateClipSearchResults() {
        let words = WordDictionary.fold(searchQuery.lowercased())
            .split(separator: " ")
            .map(String.init)
        let clips = savedClips + recentClips
        guard !words.isEmpty else {
            clipSearchResults = Array(clips.prefix(40))
            return
        }
        clipSearchResults = clips.filter { clip in
            let haystack = WordDictionary.fold(
                [clip.text, clip.folderName ?? "", clip.isImage ? "imagen foto" : ""]
                    .joined(separator: " ")
                    .lowercased()
            )
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    func pinClips(_ clips: [KeyboardClip]) {
        guard requireFullAccess() else { return }
        let recents = clips.filter { !$0.isSaved }
        recents.forEach { SharedClipboardStore.promoteTemporary(id: $0.id) }
        reloadClips()
        if !recents.isEmpty { showToast(recents.count == 1 ? "Fijado" : "\(recents.count) elementos fijados") }
    }

    func clearRecents() {
        deleteClips(recentClips)
    }

    func toggleClipSelection(_ clip: KeyboardClip) {
        if selectedClipIDs.contains(clip.id) {
            selectedClipIDs.remove(clip.id)
        } else {
            selectedClipIDs.insert(clip.id)
        }
    }

    var selectedClips: [KeyboardClip] {
        (savedClips + recentClips).filter { selectedClipIDs.contains($0.id) }
    }

    func setClipboardEnabled(_ enabled: Bool) {
        guard requireFullAccess() else { return }
        SharedClipboardStore.automaticCaptureEnabled = enabled
        clipboardEnabled = enabled
        if enabled { controller?.checkPasteboard() }
        showToast(enabled ? "Portapapeles activado" : "Portapapeles desactivado")
    }

    // MARK: Edición de texto

    func copySelection() {
        guard requireFullAccess() else { return }
        guard let text = proxy?.selectedText, !text.isEmpty else {
            showToast("Selecciona texto primero")
            return
        }
        UIPasteboard.general.string = text
        controller?.checkPasteboard()
        showToast("Copiado")
    }

    func cutSelection() {
        guard requireFullAccess() else { return }
        guard let text = proxy?.selectedText, !text.isEmpty else {
            showToast("Selecciona texto primero")
            return
        }
        UIPasteboard.general.string = text
        proxy?.deleteBackward()
        controller?.checkPasteboard()
        afterEdit()
    }

    func pasteFromPasteboard() {
        guard requireFullAccess() else { return }
        if let text = UIPasteboard.general.string, !text.isEmpty {
            proxy?.insertText(text)
            pendingAutocorrection = nil
            afterEdit()
        } else if UIPasteboard.general.hasImages {
            showToast("Las imágenes se pegan manteniendo pulsado el campo")
        } else {
            showToast("El portapapeles está vacío")
        }
    }

    // MARK: Respuesta táctil y avisos

    /// Cola propia para el sonido: `AudioServicesPlaySystemSound` espera al servidor de audio
    /// y en el hilo principal retrasaba la siguiente pulsación.
    private static let soundQueue = DispatchQueue(label: "super-teclado.key-sound", qos: .userInteractive)
    /// `true` mientras se está reproduciendo un clic. Si llega otra tecla entonces, su clic se
    /// salta: antes se ponían en cola y, al teclear deprisa, sonaban segundos después.
    private static let soundBusy = OSAllocatedUnfairLock(initialState: false)
    /// La vibración no se pide más de una vez cada 40 ms: más seguido el motor se retrasa.
    private var lastHaptic: CFTimeInterval = 0

    func keyFeedback(_ kind: KeyFeedbackKind) {
        lastKeyTouch = ProcessInfo.processInfo.systemUptime
        // Se usa el valor guardado de «acceso total»: preguntarlo a iOS en cada pulsación es lento.
        if preferences.haptics, hasFullAccess {
            let now = CACurrentMediaTime()
            if now - lastHaptic >= 0.04 {
                lastHaptic = now
                let strength = preferences.hapticsStrength
                // Las teclas especiales vibran algo más, como en Gboard.
                let intensity = kind == .character ? strength : min(1, strength + 0.2)
                let generator = hapticGenerator()
                generator.impactOccurred(intensity: CGFloat(intensity))
                // Mantiene el motor de vibración listo para la siguiente tecla, sin retraso.
                generator.prepare()
                touchDiagnostics.recordFeedback(CACurrentMediaTime() - now)
            } else {
                touchDiagnostics.skippedHaptics += 1
            }
        }
        if preferences.sound {
            let sound = SystemSoundID(preferences.soundStyle.soundID(isDelete: kind == .delete, isModifier: kind == .modifier))
            let gate = Self.soundBusy
            let starts = gate.withLock { busy -> Bool in
                guard !busy else { return false }
                busy = true
                return true
            }
            if starts {
                Self.soundQueue.async { @Sendable in
                    AudioServicesPlaySystemSound(sound)
                    gate.withLock { $0 = false }
                }
            } else {
                touchDiagnostics.skippedSounds += 1
            }
        }
    }

    /// Generador de vibración del tipo elegido; se recrea solo si cambia el tipo.
    private func hapticGenerator() -> UIImpactFeedbackGenerator {
        if let feedbackGenerator, feedbackGeneratorStyle == preferences.hapticsStyle {
            return feedbackGenerator
        }
        let generator = UIImpactFeedbackGenerator(style: preferences.hapticsStyle.feedbackStyle)
        generator.prepare()
        feedbackGenerator = generator
        feedbackGeneratorStyle = preferences.hapticsStyle
        return generator
    }

    func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        toastAction = action
        withAnimation(.easeOut(duration: 0.15)) {
            toast = message
            toastActionTitle = action == nil ? nil : actionTitle
        }
        let duration: Duration = action == nil ? .seconds(2.2) : .seconds(5)
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                self.toast = nil
                self.toastActionTitle = nil
            }
            self.toastAction = nil
        }
    }

    func performToastAction() {
        let action = toastAction
        toastTask?.cancel()
        toastAction = nil
        withAnimation(.easeIn(duration: 0.2)) {
            toast = nil
            toastActionTitle = nil
        }
        action?()
    }

    private func requireFullAccess() -> Bool {
        guard hasFullAccess else {
            showToast("Activa «Permitir acceso total» en Ajustes")
            return false
        }
        return true
    }
}
