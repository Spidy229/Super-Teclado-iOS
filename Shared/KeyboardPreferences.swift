import Foundation

enum KeyboardThemeOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var next: KeyboardThemeOption {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }
}

enum OneHandedMode: String, CaseIterable, Identifiable {
    case off
    case left
    case right

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Desactivado"
        case .left: "Mano izquierda"
        case .right: "Mano derecha"
        }
    }
}

enum KeyboardHeightOption: String, CaseIterable, Identifiable {
    case short
    case normal
    case tall
    case extraTall

    var id: Self { self }

    var title: String {
        switch self {
        case .short: "Baja"
        case .normal: "Normal"
        case .tall: "Alta"
        case .extraTall: "Muy alta"
        }
    }

    var scale: Double {
        switch self {
        case .short: 0.88
        case .normal: 1
        case .tall: 1.1
        case .extraTall: 1.2
        }
    }
}

enum KeyboardPreferenceKey {
    static let theme = "keyboardTheme"
    static let keyBorders = "keyboardKeyBorders"
    static let sound = "keyboardSound"
    static let haptics = "keyboardHaptics"
    static let autocorrect = "keyboardAutocorrect"
    static let autocapitalize = "keyboardAutocapitalize"
    static let doubleSpacePeriod = "keyboardDoubleSpacePeriod"
    static let suggestions = "keyboardSuggestions"
    static let numberRow = "keyboardNumberRow"
    static let keyPopups = "keyboardKeyPopups"
    static let longPressSymbols = "keyboardLongPressSymbols"
    static let quickPaste = "keyboardQuickPaste"
    static let oneHandedMode = "keyboardOneHandedMode"
    static let learnedWords = "keyboardLearnedWords"
    static let learnedBigrams = "keyboardLearnedBigrams"
    static let personalShortcuts = "keyboardPersonalShortcuts"
    static let glideTyping = "keyboardGlideTyping"
    static let glideTrail = "keyboardGlideTrail"
    static let nextWordPrediction = "keyboardNextWordPrediction"
    static let emojiSuggestions = "keyboardEmojiSuggestions"
    static let height = "keyboardHeight"
    static let longPressDelay = "keyboardLongPressDelay"
}

/// Ajustes del teclado compartidos entre la app y la extensión mediante el App Group.
struct KeyboardPreferences: Equatable {
    var theme: KeyboardThemeOption = .system
    var keyBorders = true
    var sound = false
    var haptics = true
    var autocorrect = true
    var autocapitalize = true
    var doubleSpacePeriod = true
    var suggestions = true
    var numberRow = false
    var keyPopups = true
    var longPressSymbols = true
    var quickPaste = true
    var oneHandedMode: OneHandedMode = .off
    var glideTyping = true
    var glideTrail = true
    var nextWordPrediction = true
    var emojiSuggestions = true
    var height: KeyboardHeightOption = .normal
    /// Milisegundos hasta mostrar acentos y símbolos al mantener una tecla.
    var longPressDelay = 330

    static func load(from defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) -> KeyboardPreferences {
        let fallback = KeyboardPreferences()
        guard let defaults else { return fallback }

        func bool(_ key: String, _ defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }

        var preferences = fallback
        preferences.theme = defaults.string(forKey: KeyboardPreferenceKey.theme)
            .flatMap(KeyboardThemeOption.init(rawValue:)) ?? fallback.theme
        preferences.keyBorders = bool(KeyboardPreferenceKey.keyBorders, fallback.keyBorders)
        preferences.sound = bool(KeyboardPreferenceKey.sound, fallback.sound)
        preferences.haptics = bool(KeyboardPreferenceKey.haptics, fallback.haptics)
        preferences.autocorrect = bool(KeyboardPreferenceKey.autocorrect, fallback.autocorrect)
        preferences.autocapitalize = bool(KeyboardPreferenceKey.autocapitalize, fallback.autocapitalize)
        preferences.doubleSpacePeriod = bool(KeyboardPreferenceKey.doubleSpacePeriod, fallback.doubleSpacePeriod)
        preferences.suggestions = bool(KeyboardPreferenceKey.suggestions, fallback.suggestions)
        preferences.numberRow = bool(KeyboardPreferenceKey.numberRow, fallback.numberRow)
        preferences.keyPopups = bool(KeyboardPreferenceKey.keyPopups, fallback.keyPopups)
        preferences.longPressSymbols = bool(KeyboardPreferenceKey.longPressSymbols, fallback.longPressSymbols)
        preferences.quickPaste = bool(KeyboardPreferenceKey.quickPaste, fallback.quickPaste)
        preferences.oneHandedMode = defaults.string(forKey: KeyboardPreferenceKey.oneHandedMode)
            .flatMap(OneHandedMode.init(rawValue:)) ?? fallback.oneHandedMode
        preferences.glideTyping = bool(KeyboardPreferenceKey.glideTyping, fallback.glideTyping)
        preferences.glideTrail = bool(KeyboardPreferenceKey.glideTrail, fallback.glideTrail)
        preferences.nextWordPrediction = bool(KeyboardPreferenceKey.nextWordPrediction, fallback.nextWordPrediction)
        preferences.emojiSuggestions = bool(KeyboardPreferenceKey.emojiSuggestions, fallback.emojiSuggestions)
        preferences.height = defaults.string(forKey: KeyboardPreferenceKey.height)
            .flatMap(KeyboardHeightOption.init(rawValue:)) ?? fallback.height
        let delay = defaults.integer(forKey: KeyboardPreferenceKey.longPressDelay)
        preferences.longPressDelay = delay > 0 ? delay : fallback.longPressDelay
        return preferences
    }

    static func setTheme(_ theme: KeyboardThemeOption) {
        SharedClipboardStore.sharedDefaults?.set(theme.rawValue, forKey: KeyboardPreferenceKey.theme)
    }

    static func setOneHandedMode(_ mode: OneHandedMode) {
        SharedClipboardStore.sharedDefaults?.set(mode.rawValue, forKey: KeyboardPreferenceKey.oneHandedMode)
    }

    static func clearLearnedWords() {
        SharedClipboardStore.sharedDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedWords)
        SharedClipboardStore.sharedDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedBigrams)
    }
}
