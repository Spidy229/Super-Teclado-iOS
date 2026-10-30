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
    }
}
