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

    /// Cambio del portapapeles hecho por el propio teclado (para no volver a capturarlo).
    var ownPasteboardChangeCount: Int?

    private let suggestionEngine = SuggestionEngine()
    private lazy var feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    private var pendingAutocorrection: (original: String, replacement: String, suffix: String)?
    private var quickPasteDate = Date.distantPast
    private var traitStyle: UIUserInterfaceStyle = .unspecified
    private var toastTask: Task<Void, Never>?
    private static let recentEmojisKey = "super-teclado-recent-emojis"

    init() {
        recentEmojis = UserDefaults.standard.stringArray(forKey: Self.recentEmojisKey) ?? []
    }

    private var proxy: (any UITextDocumentProxy)? { controller?.textDocumentProxy }

    var currentWord: String {
        KeyboardTextLogic.currentWord(before: proxy?.documentContextBeforeInput)
    }

    var hasSuggestions: Bool { suggestions.contains { $0 != nil } }

    var isWebField: Bool { keyboardType == .URL || keyboardType == .webSearch }

    var isEmailField: Bool { keyboardType == .emailAddress }

    // MARK: Contexto

    func loadPreferences() {
        let loaded = KeyboardPreferences.load()
        if loaded != preferences { preferences = loaded }
        suggestionEngine.reloadLearnedWords()
        updateAppearance()
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
        switch preferences.theme {
        case .light:
            dark = false
        case .dark:
            dark = true
        case .system:
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
        let newSuggestions: [SuggestionItem?]
        if word.isEmpty || !suggestionsAllowed {
            newSuggestions = []
        } else {
            newSuggestions = suggestionEngine.suggestions(for: word).slots
        }
        if newSuggestions != suggestions { suggestions = newSuggestions }
        if quickPaste != nil, Date().timeIntervalSince(quickPasteDate) > 180 { quickPaste = nil }
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
        guard let proxy else { return }
        let output = displayText(for: value, caseSensitive: caseSensitive)
        showsToolbar = false
        if [".", ",", "?", "!", ";", ":"].contains(output), !currentWord.isEmpty {
            commitWord(separator: output)
        } else {
            proxy.insertText(output)
            pendingAutocorrection = nil
        }
        if shift == .on { shift = .off }
        afterEdit()
    }

    func insertSpace() {
        guard let proxy else { return }
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
        proxy?.insertText("\n")
        pendingAutocorrection = nil
        afterEdit()
    }

    private func commitWord(separator: String) {
        guard let proxy else { return }
        let word = currentWord
        if !word.isEmpty,
           autocorrectAllowed,
           let correction = suggestionEngine.suggestions(for: word).autocorrection,
           correction != word {
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(correction + separator)
            pendingAutocorrection = (word, correction, separator)
            suggestionEngine.learn(correction)
        } else {
            proxy.insertText(separator)
            pendingAutocorrection = nil
            if !word.isEmpty, suggestionsAllowed { suggestionEngine.learn(word) }
        }
    }

    func deleteBackward() {
        guard let proxy else { return }
        if let pending = pendingAutocorrection,
           let context = proxy.documentContextBeforeInput,
           context.hasSuffix(pending.replacement + pending.suffix) {
            // Igual que Gboard: borrar justo después de una corrección la deshace.
            for _ in 0..<(pending.replacement.count + pending.suffix.count) { proxy.deleteBackward() }
            proxy.insertText(pending.original)
            suggestionEngine.reject(pending.original)
        } else {
            proxy.deleteBackward()
        }
        pendingAutocorrection = nil
        afterEdit()
    }

    func deleteWordBackward() {
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
        for _ in 0..<word.count { proxy.deleteBackward() }
        proxy.insertText(item.text + " ")
        if item.kind == .typed {
            suggestionEngine.reject(item.text)
        } else {
            suggestionEngine.learn(item.text)
        }
        pendingAutocorrection = nil
        lastSpaceTap = .distantPast
        afterEdit()
    }

    func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        proxy?.adjustTextPosition(byCharacterOffset: offset)
        pendingAutocorrection = nil
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
        var recents = recentEmojis.filter { $0 != emoji }
        recents.insert(emoji, at: 0)
        recentEmojis = Array(recents.prefix(32))
        UserDefaults.standard.set(recentEmojis, forKey: Self.recentEmojisKey)
        afterEdit()
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

    func cycleTheme() {
        let theme = preferences.theme.next
        preferences.theme = theme
        KeyboardPreferences.setTheme(theme)
        updateAppearance()
        showToast("Tema: \(theme.title)")
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

    func useClip(_ clip: KeyboardClip) {
        if clip.isImage {
            copyClip(clip)
            return
        }
        proxy?.insertText(clip.text)
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
        SharedClipboardStore.deleteSaved(ids: Set(clips.filter(\.isSaved).map(\.id)))
        SharedClipboardStore.deleteTemporary(ids: Set(clips.filter { !$0.isSaved }.map(\.id)))
        if let quickPaste, clips.contains(where: { $0.id == quickPaste.id }) { self.quickPaste = nil }
        reloadClips()
        showToast(clips.count == 1 ? "Eliminado" : "\(clips.count) elementos eliminados")
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
            feedbackGenerator.impactOccurred(intensity: kind == .character ? 0.55 : 0.75)
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

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { toast = message }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.toast = nil }
        }
    }

    private func requireFullAccess() -> Bool {
        guard hasFullAccess else {
            showToast("Activa «Permitir acceso total» en Ajustes")
            return false
        }
        return true
    }
}
