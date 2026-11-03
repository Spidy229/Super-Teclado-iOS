import SwiftUI

/// Colores de cada tema, inspirados en los de Gboard. Está en `Shared` para que la app pueda
/// mostrar la vista previa de los temas con los mismos colores que el teclado.
struct KeyboardPalette {
    let background: Color
    let key: Color
    let specialKey: Color
    let keyPressed: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let accentText: Color
    let shadow: Color
    let popup: Color
    let tile: Color
    let chip: Color
    let separator: Color

    static func make(
        theme: KeyboardThemeOption,
        systemIsDark: Bool,
        custom: CustomThemeColors = CustomThemeColors()
    ) -> KeyboardPalette {
        switch theme {
        case .system: systemIsDark ? dark : light
        case .light: light
        case .dark: dark
        case .black: black
        case .ocean:
            tinted(
                background: rgb(0.05, 0.16, 0.29),
                key: rgb(0.11, 0.27, 0.45),
                specialKey: rgb(0.08, 0.21, 0.37),
                accent: rgb(0.55, 0.8, 1)
            )
        case .forest:
            tinted(
                background: rgb(0.06, 0.18, 0.13),
                key: rgb(0.12, 0.3, 0.22),
                specialKey: rgb(0.09, 0.24, 0.17),
                accent: rgb(0.55, 0.88, 0.65)
            )
        case .sunset:
            tinted(
                background: rgb(0.25, 0.11, 0.1),
                key: rgb(0.41, 0.19, 0.15),
                specialKey: rgb(0.33, 0.15, 0.12),
                accent: rgb(1, 0.67, 0.42)
            )
        case .rose:
            pastel(
                background: rgb(0.99, 0.89, 0.93),
                specialKey: rgb(0.96, 0.76, 0.85),
                accent: rgb(0.84, 0.21, 0.47)
            )
        case .lavender:
            pastel(
                background: rgb(0.92, 0.9, 0.99),
                specialKey: rgb(0.82, 0.78, 0.96),
                accent: rgb(0.45, 0.31, 0.85)
            )
        case .photo: photo
        case .custom: customPalette(custom)
        }
    }

    static func color(_ value: RGBColor) -> Color {
        rgb(value.red, value.green, value.blue)
    }

    /// Paleta a partir de los cuatro colores que elige el usuario.
    private static func customPalette(_ colors: CustomThemeColors) -> KeyboardPalette {
        let text = color(colors.text)
        let key = color(colors.key)
        let darkText = colors.text.luminance < 0.5
        return KeyboardPalette(
            background: color(colors.background),
            key: key,
            specialKey: key.opacity(0.62),
            keyPressed: text.opacity(0.28),
            text: text,
            secondaryText: text.opacity(0.65),
            accent: color(colors.accent),
            accentText: colors.accent.luminance > 0.55 ? rgb(0.08, 0.09, 0.11) : .white,
            shadow: Color.black.opacity(darkText ? 0.18 : 0.4),
            popup: key,
            tile: key.opacity(0.9),
            chip: key.opacity(0.7),
            separator: text.opacity(0.16)
        )
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }

    private static let dark = KeyboardPalette(
        background: rgb(0.125, 0.129, 0.141),
        key: rgb(0.275, 0.282, 0.298),
        specialKey: rgb(0.2, 0.208, 0.22),
        keyPressed: rgb(0.38, 0.39, 0.41),
        text: rgb(0.91, 0.918, 0.929),
        secondaryText: rgb(0.6, 0.62, 0.64),
        accent: rgb(0.541, 0.706, 0.973),
        accentText: rgb(0.11, 0.12, 0.14),
        shadow: Color.black.opacity(0.45),
        popup: rgb(0.33, 0.34, 0.36),
        tile: rgb(0.235, 0.243, 0.259),
        chip: rgb(0.2, 0.208, 0.22),
        separator: Color.white.opacity(0.14)
    )

    private static let light = KeyboardPalette(
        background: rgb(0.91, 0.918, 0.933),
        key: .white,
        specialKey: rgb(0.792, 0.808, 0.835),
        keyPressed: rgb(0.72, 0.74, 0.77),
        text: rgb(0.125, 0.129, 0.141),
        secondaryText: rgb(0.37, 0.39, 0.41),
        accent: rgb(0.102, 0.451, 0.91),
        accentText: .white,
        shadow: Color.black.opacity(0.22),
        popup: .white,
        tile: .white,
        chip: rgb(0.84, 0.855, 0.875),
        separator: Color.black.opacity(0.12)
    )

    private static let black = KeyboardPalette(
        background: .black,
        key: rgb(0.13, 0.13, 0.14),
        specialKey: rgb(0.07, 0.07, 0.08),
        keyPressed: rgb(0.26, 0.26, 0.28),
        text: rgb(0.93, 0.93, 0.94),
        secondaryText: rgb(0.55, 0.56, 0.58),
        accent: rgb(0.541, 0.706, 0.973),
        accentText: rgb(0.05, 0.05, 0.06),
        shadow: .clear,
        popup: rgb(0.2, 0.2, 0.22),
        tile: rgb(0.12, 0.12, 0.13),
        chip: rgb(0.15, 0.15, 0.16),
        separator: Color.white.opacity(0.14)
    )

    /// Teclas semitransparentes sobre la foto del usuario.
    private static let photo = KeyboardPalette(
        background: .black,
        key: Color.white.opacity(0.22),
        specialKey: Color.white.opacity(0.12),
        keyPressed: Color.white.opacity(0.42),
        text: .white,
        secondaryText: Color.white.opacity(0.72),
        accent: rgb(0.541, 0.706, 0.973),
        accentText: rgb(0.08, 0.09, 0.11),
        shadow: Color.black.opacity(0.25),
        popup: rgb(0.24, 0.25, 0.27),
        tile: Color.white.opacity(0.18),
        chip: Color.white.opacity(0.16),
        separator: Color.white.opacity(0.22)
    )

    private static func tinted(background: Color, key: Color, specialKey: Color, accent: Color) -> KeyboardPalette {
        KeyboardPalette(
            background: background,
            key: key,
            specialKey: specialKey,
            keyPressed: key.opacity(0.6),
            text: .white,
            secondaryText: Color.white.opacity(0.65),
            accent: accent,
            accentText: rgb(0.08, 0.09, 0.11),
            shadow: Color.black.opacity(0.4),
            popup: key,
            tile: key.opacity(0.85),
            chip: specialKey,
            separator: Color.white.opacity(0.16)
        )
    }

    private static func pastel(background: Color, specialKey: Color, accent: Color) -> KeyboardPalette {
        KeyboardPalette(
            background: background,
            key: .white,
            specialKey: specialKey,
            keyPressed: specialKey.opacity(0.7),
            text: rgb(0.16, 0.13, 0.18),
            secondaryText: rgb(0.42, 0.38, 0.45),
            accent: accent,
            accentText: .white,
            shadow: Color.black.opacity(0.15),
            popup: .white,
            tile: .white,
            chip: specialKey,
            separator: Color.black.opacity(0.1)
        )
    }
}
