import Foundation

enum KeyboardThemeOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case black
    case glass
    case ocean
    case forest
    case sunset
    case rose
    case lavender
    case aurora
    case dawn
    case mint
    case night
    case photo
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        case .black: "Negro"
        case .glass: "Cristal"
        case .ocean: "Océano"
        case .forest: "Bosque"
        case .sunset: "Atardecer"
        case .rose: "Rosa"
        case .lavender: "Lavanda"
        case .aurora: "Aurora"
        case .dawn: "Amanecer"
        case .mint: "Menta"
        case .night: "Noche"
        case .photo: "Mi foto"
        case .custom: "Personalizado"
        }
    }

    /// `nil` cuando depende del sistema (Automático) o de los colores elegidos (Personalizado).
    var isDark: Bool? {
        switch self {
        case .system, .custom, .glass: nil
        case .light, .rose, .lavender, .dawn: false
        case .dark, .black, .ocean, .forest, .sunset, .photo, .aurora, .mint, .night: true
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
    static let incognito = "keyboardIncognito"
    /// Elegir entre dos teclas según la palabra que se está escribiendo al tocar entre ellas.
    static let smartTouch = "keyboardSmartTouch"
    /// Clave antigua (versión 2.2): inglés como segundo idioma.
    static let englishSecondLanguage = "keyboardEnglishSecondLanguage"
    static let primaryLanguage = "keyboardPrimaryLanguage"
    /// Código del segundo idioma, o cadena vacía si no hay.
    static let secondaryLanguage = "keyboardSecondaryLanguage"
    /// Distribución elegida, o «auto» para usar la del idioma principal.
    static let layout = "keyboardLayout"
    static let soundStyle = "keyboardSoundStyle"
    static let favoritesRow = "keyboardFavoritesRow"
    static let favorites = "keyboardFavorites"
    static let customBackgroundEnd = "keyboardCustomBackgroundEnd"
    static let backgroundDim = "keyboardBackgroundDim"
    static let hapticsStrength = "keyboardHapticsStrength"
    /// Transparencia del tema «Cristal»: 1 deja ver del todo el fondo translúcido de iOS.
    static let glassTransparency = "keyboardGlassTransparency"
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
    /// Antes 330 ms: con eso un toque algo lento escribía el número de la esquina.
    var longPressDelay = 400
    /// Sin aprender palabras ni guardar lo copiado.
    var incognito = false
    var smartTouch = true
    var primaryLanguage: KeyboardLanguage = .spanish
    var secondaryLanguage: KeyboardLanguage?
    /// `nil` usa la distribución del idioma principal.
    var layoutOverride: LetterLayout?
    var soundStyle: KeySoundStyle = .modern
    var favoritesRow = false
    var favorites = KeyboardPreferences.defaultFavorites
    /// Oscurecimiento de la foto de fondo (0 a 0,7).
    var backgroundDim = 0.35
    var glassTransparency = 1.0
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
        // 330 era el valor «Normal» anterior: pasa al nuevo normal.
        preferences.longPressDelay = delay > 0 && delay != 330 ? delay : fallback.longPressDelay
        preferences.incognito = bool(KeyboardPreferenceKey.incognito, fallback.incognito)
        preferences.smartTouch = bool(KeyboardPreferenceKey.smartTouch, fallback.smartTouch)
        preferences.primaryLanguage = defaults.string(forKey: KeyboardPreferenceKey.primaryLanguage)
            .flatMap(KeyboardLanguage.init(rawValue:)) ?? fallback.primaryLanguage
        if let code = defaults.string(forKey: KeyboardPreferenceKey.secondaryLanguage) {
            preferences.secondaryLanguage = KeyboardLanguage(rawValue: code)
        } else if defaults.bool(forKey: KeyboardPreferenceKey.englishSecondLanguage) {
            preferences.secondaryLanguage = .english
        }
        if preferences.secondaryLanguage == preferences.primaryLanguage { preferences.secondaryLanguage = nil }
        preferences.layoutOverride = defaults.string(forKey: KeyboardPreferenceKey.layout)
            .flatMap(LetterLayout.init(rawValue:))
        preferences.soundStyle = defaults.string(forKey: KeyboardPreferenceKey.soundStyle)
            .flatMap(KeySoundStyle.init(rawValue:)) ?? fallback.soundStyle
        preferences.favoritesRow = bool(KeyboardPreferenceKey.favoritesRow, fallback.favoritesRow)
        if let favorites = defaults.string(forKey: KeyboardPreferenceKey.favorites) {
            preferences.favorites = favorites
        }
        if defaults.object(forKey: KeyboardPreferenceKey.backgroundDim) != nil {
            preferences.backgroundDim = min(max(defaults.double(forKey: KeyboardPreferenceKey.backgroundDim), 0), 0.7)
        }
        if defaults.object(forKey: KeyboardPreferenceKey.glassTransparency) != nil {
            preferences.glassTransparency = min(max(defaults.double(forKey: KeyboardPreferenceKey.glassTransparency), 0), 1)
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

    static let defaultFavorites = "😂❤️👍🙏😍🔥✨😊🎉👏@#€¿¡"

    /// Distribución en uso: la elegida o la del idioma principal.
    var letterLayout: LetterLayout { layoutOverride ?? primaryLanguage.defaultLayout }

    /// Emojis y símbolos de la fila de favoritos.
    var favoriteItems: [String] {
        favorites.filter { !$0.isWhitespace }.map(String.init)
    }

    /// Guarda todos los ajustes (los que se cambian desde el propio teclado).
    func save(to defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        guard let defaults else { return }
        let values: [String: Any] = [
            KeyboardPreferenceKey.theme: theme.rawValue,
            KeyboardPreferenceKey.keyBorders: keyBorders,
            KeyboardPreferenceKey.sound: sound,
            KeyboardPreferenceKey.haptics: haptics,
            KeyboardPreferenceKey.autocorrect: autocorrect,
            KeyboardPreferenceKey.autocapitalize: autocapitalize,
            KeyboardPreferenceKey.doubleSpacePeriod: doubleSpacePeriod,
            KeyboardPreferenceKey.suggestions: suggestions,
            KeyboardPreferenceKey.numberRow: numberRow,
            KeyboardPreferenceKey.keyPopups: keyPopups,
            KeyboardPreferenceKey.longPressSymbols: longPressSymbols,
            KeyboardPreferenceKey.quickPaste: quickPaste,
            KeyboardPreferenceKey.oneHandedMode: oneHandedMode.rawValue,
            KeyboardPreferenceKey.glideTyping: glideTyping,
            KeyboardPreferenceKey.glideTrail: glideTrail,
            KeyboardPreferenceKey.nextWordPrediction: nextWordPrediction,
            KeyboardPreferenceKey.emojiSuggestions: emojiSuggestions,
            KeyboardPreferenceKey.height: height.rawValue,
            KeyboardPreferenceKey.longPressDelay: longPressDelay,
            KeyboardPreferenceKey.incognito: incognito,
            KeyboardPreferenceKey.smartTouch: smartTouch,
            KeyboardPreferenceKey.backgroundDim: backgroundDim,
            KeyboardPreferenceKey.glassTransparency: glassTransparency,
            KeyboardPreferenceKey.hapticsStrength: hapticsStrength,
            KeyboardPreferenceKey.hapticsStyle: hapticsStyle.rawValue,
            KeyboardPreferenceKey.keyLabelSize: keyLabelSize.rawValue,
            KeyboardPreferenceKey.primaryLanguage: primaryLanguage.rawValue,
            KeyboardPreferenceKey.secondaryLanguage: secondaryLanguage?.rawValue ?? "",
            KeyboardPreferenceKey.layout: layoutOverride?.rawValue ?? "auto",
            KeyboardPreferenceKey.soundStyle: soundStyle.rawValue,
            KeyboardPreferenceKey.favoritesRow: favoritesRow,
            KeyboardPreferenceKey.favorites: favorites
        ]
        for (key, value) in values { defaults.set(value, forKey: key) }
        customColors.save(to: defaults)
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

    /// Se redondea a 8 bits por canal, igual que al guardarlo, para que guardar y volver a
    /// leer dé exactamente el mismo color.
    init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> Double { (min(max(value, 0), 1) * 255).rounded() / 255 }
        self.red = channel(red)
        self.green = channel(green)
        self.blue = channel(blue)
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

    /// Segundo color del fondo para un degradado (`nil` = color liso).
    var backgroundEnd: RGBColor?

    var isDark: Bool {
        let end = backgroundEnd?.luminance ?? background.luminance
        return (background.luminance + end) / 2 < 0.5
    }

    static func load(from defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) -> CustomThemeColors {
        var colors = CustomThemeColors()
        func color(_ key: String) -> RGBColor? { defaults?.string(forKey: key).flatMap(RGBColor.init(hex:)) }
        if let value = color(KeyboardPreferenceKey.customBackground) { colors.background = value }
        if let value = color(KeyboardPreferenceKey.customKey) { colors.key = value }
        if let value = color(KeyboardPreferenceKey.customText) { colors.text = value }
        if let value = color(KeyboardPreferenceKey.customAccent) { colors.accent = value }
        colors.backgroundEnd = color(KeyboardPreferenceKey.customBackgroundEnd)
        return colors
    }

    func save(to defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        defaults?.set(background.hex, forKey: KeyboardPreferenceKey.customBackground)
        defaults?.set(key.hex, forKey: KeyboardPreferenceKey.customKey)
        defaults?.set(text.hex, forKey: KeyboardPreferenceKey.customText)
        defaults?.set(accent.hex, forKey: KeyboardPreferenceKey.customAccent)
        defaults?.set(backgroundEnd?.hex ?? "", forKey: KeyboardPreferenceKey.customBackgroundEnd)
    }
}

/// Sonido de las teclas (sonidos del sistema de iOS).
enum KeySoundStyle: String, CaseIterable, Identifiable {
    case modern
    case classic
    case crystal
    case phone

    var id: Self { self }

    var title: String {
        switch self {
        case .modern: "Moderno"
        case .classic: "Clásico"
        case .crystal: "Cristal"
        case .phone: "Teléfono"
        }
    }

    /// Identificador de `SystemSoundID` para cada tipo de tecla.
    func soundID(isDelete: Bool, isModifier: Bool) -> UInt32 {
        switch self {
        case .modern:
            return isDelete ? 1155 : (isModifier ? 1156 : 1123)
        case .classic:
            return 1104
        case .crystal:
            return isDelete || isModifier ? 1104 : 1103
        case .phone:
            // Tonos de marcación: un dígito al azar para las letras, # y * para el resto.
            if isDelete { return 1210 }
            if isModifier { return 1211 }
            return 1200 + UInt32.random(in: 0...9)
        }
    }
}
