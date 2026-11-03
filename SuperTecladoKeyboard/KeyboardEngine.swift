import AudioToolbox
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum KeyFeedbackKind {
    case character
    case delete
    case modifier
}

/// Estado y lógica del teclado. Las vistas SwiftUI solo leen este objeto y le envían acciones.
@MainActor
final class KeyboardEngine: ObservableObject {
    weak var controller: KeyboardViewController?

    @Published var panel: KeyboardPanel = .typing
    @Published var page: KeyboardPage = .letters
    @Published var shift: ShiftState = .off
    @Published var suggestions: [SuggestionItem?] = []
    @Published var showsToolbar = false
    @Published var quickPaste: KeyboardClip?
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
    @Published var isCursorMode = false
    @Published private(set) var isGliding = false
    @Published private(set) var backgroundImage: UIImage?
    @Published private(set) var searchQuery = ""
    @Published private(set) var emojiSearchResults: [String] = []
    @Published private(set) var emojiTones: [String: String] = [:]
    @Published private(set) var clipSearchResults: [KeyboardClip] = []
    @Published private(set) var toastActionTitle: String?

    let glideTrail = GlideTrail()

    /// Cambio del portapapeles hecho por el propio teclado (para no volver a capturarlo).
    var ownPasteboardChangeCount: Int?

    private let suggestionEngine = SuggestionEngine()
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    private var feedbackGeneratorStyle: HapticStyleOption?
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    private var pendingAutocorrection: (original: String, replacement: String, suffix: String)?
    private var quickPasteDate = Date.distantPast
    private var traitStyle: UIUserInterfaceStyle = .unspecified
    private var toastTask: Task<Void, Never>?
    private var toastAction: (() -> Void)?
    /// Último borrado del portapapeles, para poder deshacerlo durante unos segundos.
    private var undoDeletion: (saved: [SharedClipboardClip], temporary: [SharedTemporaryClip])?
    private var undoTask: Task<Void, Never>?
    private var glidePoints: [CGPoint] = []
    private var glideGridSize: CGSize = .zero
    /// Última palabra escrita deslizando y sus alternativas, para cambiarla desde la barra.
    private var lastGlide: (word: String, alternatives: [String])?
    /// Espacio añadido automáticamente tras elegir una sugerencia (se quita ante un signo).
    private var autoSpaceInserted = false
    /// Idiomas del diccionario cargado (`nil` mientras no se ha cargado ninguno).
    private var loadedEnglish: Bool?
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

    var hasSuggestions: Bool { suggestions.contains { $0 != nil } }

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
        return preferences.englishSecondLanguage ? "Español · English" : "Español"
    }

    // MARK: Contexto

    func loadPreferences() {
        let loaded = KeyboardPreferences.load()
        if loaded != preferences { preferences = loaded }
        suggestionEngine.reloadPersonalData()
        updateAppearance()
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
        updateShiftState()
        refreshSuggestions()
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
        let english = preferences.englishSecondLanguage
        guard loadedEnglish != english,
              let url = Bundle.main.url(forResource: "es-palabras", withExtension: "txt") else { return }
        loadedEnglish = english
        let englishURL = english ? Bundle.main.url(forResource: "en-words", withExtension: "txt") : nil
        Task { [weak self] in
            let dictionary = await Task.detached(priority: .userInitiated) {
                WordDictionary.load(from: url, secondary: englishURL, secondaryWeight: 0.6)
            }.value
            guard let self, let dictionary, self.loadedEnglish == english else { return }
            self.suggestionEngine.setDictionary(dictionary)
            self.refreshSuggestions()
        }
    }

    /// Restablece la página al empezar a escribir en otro campo, como Gboard.
    func prepareForNewField() {
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

    private func refreshSuggestions() {
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
            newSuggestions = suggestionEngine.suggestions(
                for: word,
                includeEmoji: preferences.emojiSuggestions
            ).slots
        }
        if newSuggestions != suggestions { suggestions = newSuggestions }
        if quickPaste != nil, Date().timeIntervalSince(quickPasteDate) > 180 { quickPaste = nil }
    }

    private func predictions() -> [SuggestionItem?] {
        guard preferences.nextWordPrediction,
              let context = proxy?.documentContextBeforeInput, context.hasSuffix(" "),
              let previous = KeyboardTextLogic.previousWord(before: context) else { return [] }
        return suggestionEngine.predictions(after: previous)
    }

    /// Aprende la palabra y el par «palabra anterior → palabra» para predecir.
    private func recordWord(_ word: String, context: String?) {
        guard suggestionsAllowed, !isIncognito, !word.isEmpty else { return }
        suggestionEngine.learn(word)
        if preferences.nextWordPrediction, let previous = KeyboardTextLogic.previousWord(before: context) {
            suggestionEngine.learnBigram(previous: previous, word: word)
        }
    }

    private func afterEdit() {
        updateShiftState()
        refreshSuggestions()
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
        showsToolbar = false
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
        afterEdit()
    }

    func insertSpace() {
        if isSearching {
            if !searchQuery.isEmpty, !searchQuery.hasSuffix(" ") {
                setSearchQuery(searchQuery + " ")
            }
            return
        }
        guard let proxy else { return }
        autoSpaceInserted = false
        let now = Date()
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
           let correction = suggestionEngine.suggestions(for: word, includeEmoji: false).autocorrection,
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
            proxy.insertText(word.isEmpty ? item.text + " " : " " + item.text + " ")
            recordWord(word, context: context)
            rememberEmoji(item.text)
            lastGlide = nil
            autoSpaceInserted = true
        case .prediction:
            proxy.insertText(item.text + " ")
            recordWord(item.text, context: context)
            autoSpaceInserted = true
        case .typed, .correction, .completion:
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(item.text + " ")
            if item.kind == .typed { suggestionEngine.reject(item.text, persist: !isIncognito) }
            recordWord(item.text, context: context)
            lastGlide = nil
            autoSpaceInserted = true
        }
        if shift == .on { shift = .off }
        afterEdit()
    }

    // MARK: Escritura deslizando

    var canGlide: Bool {
        preferences.glideTyping && panel == .typing && page == .letters
            && !isWebField && !isEmailField && suggestionEngine.dictionary != nil
    }

    func beginGlide(at point: CGPoint, gridSize: CGSize) {
        glidePoints = [point]
        glideGridSize = gridSize
        isGliding = true
        if preferences.glideTrail { glideTrail.begin(at: point) }
    }

    func extendGlide(to point: CGPoint) {
        guard isGliding, let last = glidePoints.last, GlideDecoder.distance(last, point) >= 2 else { return }
        glidePoints.append(point)
        if preferences.glideTrail { glideTrail.add(point) }
    }

    /// Devuelve `false` si el trazo fue tan corto que debe tratarse como una pulsación normal.
    @discardableResult
    func endGlide() -> Bool {
        guard isGliding else { return true }
        isGliding = false
        glideTrail.finish()
        let path = glidePoints
        glidePoints = []
        let geometry = KeyGridGeometry(
            size: glideGridSize,
            showsNumberRow: preferences.numberRow,
            rowCount: preferences.numberRow ? 5 : 4
        )
        guard GlideDecoder.length(of: path) >= Double(geometry.unit) * 0.9 else { return false }
        guard let proxy, let dictionary = suggestionEngine.dictionary else { return true }

        let decoder = GlideDecoder(keyCenters: geometry.letterCenters(), keyWidth: geometry.unit)
        let candidates = decoder.decode(
            path: path,
            dictionary: dictionary,
            extraWords: suggestionEngine.glideExtraWords,
            limit: 4
        )
        guard !candidates.isEmpty else {
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
        showsToolbar = false
        lastGlide = (styled[0], styled)
        if shift == .on { shift = .off }
        afterEdit()
        return true
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

    func setTheme(_ theme: KeyboardThemeOption) {
        preferences.theme = theme
        KeyboardPreferences.setTheme(theme)
        updateAppearance()
        loadBackgroundIfNeeded()
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
        let saved = SharedClipboardStore.load().map(KeyboardClip.init(saved:))
        let recent = SharedClipboardStore.loadTemporaryInbox().map(KeyboardClip.init(recent:))
        if saved != savedClips { savedClips = saved }
        if recent != recentClips { recentClips = recent }
        let loadedFolders = SharedClipboardStore.loadFolders()
        if loadedFolders != folders { folders = loadedFolders }
        let enabled = SharedClipboardStore.automaticCaptureEnabled
        if enabled != clipboardEnabled { clipboardEnabled = enabled }
        selectedClipIDs = selectedClipIDs.filter { id in
            saved.contains { $0.id == id } || recent.contains { $0.id == id }
        }
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

    func keyFeedback(_ kind: KeyFeedbackKind) {
        if preferences.haptics, hasFullAccess {
            let strength = preferences.hapticsStrength
            // Las teclas especiales vibran algo más, como en Gboard.
            let intensity = kind == .character ? strength : min(1, strength + 0.2)
            hapticGenerator().impactOccurred(intensity: CGFloat(intensity))
        }
        if preferences.sound {
            let sound: SystemSoundID = switch kind {
            case .character: 1104
            case .delete: 1155
            case .modifier: 1156
            }
            AudioServicesPlaySystemSound(sound)
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
