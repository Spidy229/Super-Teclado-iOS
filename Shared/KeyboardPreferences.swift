import Foundation

enum KeyboardThemeOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case black
    case ocean
    case forest
    case sunset
    case rose
    case lavender
    case photo
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        case .black: "Negro"
        case .ocean: "Océano"
        case .forest: "Bosque"
        case .sunset: "Atardecer"
        case .rose: "Rosa"
        case .lavender: "Lavanda"
        case .photo: "Mi foto"
        case .custom: "Personalizado"
        }
    }

    /// `nil` cuando depende del sistema (Automático) o de los colores elegidos (Personalizado).
    var isDark: Bool? {
        switch self {
        case .system, .custom: nil
        case .light, .rose, .lavender: false
        case .dark, .black, .ocean, .forest, .sunset, .photo: true
        }
    }

    /// Siguiente tema al tocar el botón de la barra (la foto solo si hay una elegida).
    func next(includingPhoto: Bool) -> KeyboardThemeOption {
        let options = Self.allCases.filter { $0 != .photo || includingPhoto }
        guard let index = options.firstIndex(of: self) else { return .system }
        return options[(index + 1) % options.count]
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
    static let incognito = "keyboardIncognito"
    static let englishSecondLanguage = "keyboardEnglishSecondLanguage"
    static let backgroundDim = "keyboardBackgroundDim"
    static let hapticsStrength = "keyboardHapticsStrength"
    static let hapticsStyle = "keyboardHapticsStyle"
    static let keyLabelSize = "keyboardKeyLabelSize"
    static let customBackground = "keyboardCustomBackground"
    static let customKey = "keyboardCustomKey"
    static let customText = "keyboardCustomText"
    static let customAccent = "keyboardCustomAccent"
    /// Última vez que se abrió el teclado con acceso total (para el estado en la app).
    static let lastActive = "keyboardLastActive"
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
    /// Sin aprender palabras ni guardar lo copiado.
    var incognito = false
    var englishSecondLanguage = false
    /// Oscurecimiento de la foto de fondo (0 a 0,7).
    var backgroundDim = 0.35
    /// Intensidad de la vibración de 0,1 a 1.
    var hapticsStrength = 0.6
    var hapticsStyle: HapticStyleOption = .light
    var keyLabelSize: KeyLabelSize = .normal
    var customColors = CustomThemeColors()

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
        preferences.incognito = bool(KeyboardPreferenceKey.incognito, fallback.incognito)
        preferences.englishSecondLanguage = bool(
            KeyboardPreferenceKey.englishSecondLanguage,
            fallback.englishSecondLanguage
        )
        if defaults.object(forKey: KeyboardPreferenceKey.backgroundDim) != nil {
            preferences.backgroundDim = min(max(defaults.double(forKey: KeyboardPreferenceKey.backgroundDim), 0), 0.7)
        }
        if defaults.object(forKey: KeyboardPreferenceKey.hapticsStrength) != nil {
            preferences.hapticsStrength = min(max(defaults.double(forKey: KeyboardPreferenceKey.hapticsStrength), 0.1), 1)
        }
        preferences.hapticsStyle = defaults.string(forKey: KeyboardPreferenceKey.hapticsStyle)
            .flatMap(HapticStyleOption.init(rawValue:)) ?? fallback.hapticsStyle
        preferences.keyLabelSize = defaults.string(forKey: KeyboardPreferenceKey.keyLabelSize)
            .flatMap(KeyLabelSize.init(rawValue:)) ?? fallback.keyLabelSize
        preferences.customColors = CustomThemeColors.load(from: defaults)
        return preferences
    }

    static func setKeyBorders(_ enabled: Bool) {
        SharedClipboardStore.sharedDefaults?.set(enabled, forKey: KeyboardPreferenceKey.keyBorders)
    }

    static func setTheme(_ theme: KeyboardThemeOption) {
        SharedClipboardStore.sharedDefaults?.set(theme.rawValue, forKey: KeyboardPreferenceKey.theme)
    }

    static func setIncognito(_ enabled: Bool) {
        SharedClipboardStore.sharedDefaults?.set(enabled, forKey: KeyboardPreferenceKey.incognito)
    }

    static func setOneHandedMode(_ mode: OneHandedMode) {
        SharedClipboardStore.sharedDefaults?.set(mode.rawValue, forKey: KeyboardPreferenceKey.oneHandedMode)
    }

    static func clearLearnedWords() {
        SharedClipboardStore.sharedDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedWords)
        SharedClipboardStore.sharedDefaults?.removeObject(forKey: KeyboardPreferenceKey.learnedBigrams)
    }
}

/// Tipo de vibración de las teclas (se traduce a `UIImpactFeedbackGenerator`).
enum HapticStyleOption: String, CaseIterable, Identifiable {
    case soft
    case light
    case medium
    case rigid
    case heavy

    var id: Self { self }

    var title: String {
        switch self {
        case .soft: "Suave"
        case .light: "Ligera"
        case .medium: "Media"
        case .rigid: "Seca"
        case .heavy: "Fuerte"
        }
    }
}

enum KeyLabelSize: String, CaseIterable, Identifiable {
    case small
    case normal
    case large

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Pequeño"
        case .normal: "Normal"
        case .large: "Grande"
        }
    }

    var scale: Double {
        switch self {
        case .small: 0.86
        case .normal: 1
        case .large: 1.14
        }
    }
}

/// Color guardado como «RRGGBB».
struct RGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    var hex: String {
        String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// Luminancia relativa aproximada (0 = negro, 1 = blanco).
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// Colores del tema «Personalizado».
struct CustomThemeColors: Equatable {
    var background = RGBColor(red: 0.12, green: 0.16, blue: 0.22)
    var key = RGBColor(red: 0.18, green: 0.25, blue: 0.34)
    var text = RGBColor(red: 1, green: 1, blue: 1)
    var accent = RGBColor(red: 1, green: 0.72, blue: 0.3)

    var isDark: Bool { background.luminance < 0.5 }

    static func load(from defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) -> CustomThemeColors {
        var colors = CustomThemeColors()
        func color(_ key: String) -> RGBColor? { defaults?.string(forKey: key).flatMap(RGBColor.init(hex:)) }
        if let value = color(KeyboardPreferenceKey.customBackground) { colors.background = value }
        if let value = color(KeyboardPreferenceKey.customKey) { colors.key = value }
        if let value = color(KeyboardPreferenceKey.customText) { colors.text = value }
        if let value = color(KeyboardPreferenceKey.customAccent) { colors.accent = value }
        return colors
    }

    func save(to defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        defaults?.set(background.hex, forKey: KeyboardPreferenceKey.customBackground)
        defaults?.set(key.hex, forKey: KeyboardPreferenceKey.customKey)
        defaults?.set(text.hex, forKey: KeyboardPreferenceKey.customText)
        defaults?.set(accent.hex, forKey: KeyboardPreferenceKey.customAccent)
    }
}
