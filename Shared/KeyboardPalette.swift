import SwiftUI

/// Colores de cada tema, inspirados en los de Gboard. Está en `Shared` para que la app pueda
/// mostrar la vista previa de los temas con los mismos colores que el teclado.
struct KeyboardPalette: Equatable {
    var background: Color
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
    /// Colores del fondo en degradado (de arriba a la izquierda hacia abajo a la derecha).
    var gradient: [Color]? = nil
    /// Fondo opaco para paneles que tapan el teclado cuando el fondo es transparente.
    var solidBackground: Color? = nil

    var opaqueBackground: Color { solidBackground ?? gradient?.first ?? background }

    static func make(
        theme: KeyboardThemeOption,
        systemIsDark: Bool,
        custom: CustomThemeColors = CustomThemeColors(),
        glassTransparency: Double = 1
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
        case .glass: glass(dark: systemIsDark, transparency: glassTransparency)
        case .aurora:
            gradientPalette([rgb(0.23, 0.11, 0.44), rgb(0.12, 0.31, 0.61)], dark: true, accent: rgb(0.8, 0.65, 1))
        case .dawn:
            gradientPalette([rgb(0.97, 0.47, 0.49), rgb(0.98, 0.84, 0.53)], dark: false, accent: rgb(0.72, 0.2, 0.3))
        case .mint:
            gradientPalette([rgb(0.04, 0.45, 0.42), rgb(0.18, 0.63, 0.45)], dark: true, accent: rgb(0.75, 1, 0.85))
        case .night:
            gradientPalette([rgb(0.06, 0.13, 0.15), rgb(0.17, 0.33, 0.39)], dark: true, accent: rgb(0.55, 0.85, 0.95))
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
            separator: text.opacity(0.16),
            gradient: colors.backgroundEnd.map { [color(colors.background), color($0)] }
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

    /// Cristal con la transparencia elegida: un velo del color de fondo sobre el fondo
    /// translúcido de iOS, de nada (100 %) a opaco (0 %).
    private static func glass(dark: Bool, transparency: Double) -> KeyboardPalette {
        var palette = dark ? darkGlass : lightGlass
        let veil = 1 - min(max(transparency, 0), 1)
        if veil > 0.001 {
            palette.background = (palette.solidBackground ?? palette.background).opacity(veil)
        }
        return palette
    }

    /// Cristal: fondo transparente sobre el fondo translúcido del sistema.
    private static let darkGlass = KeyboardPalette(
        background: .clear,
        key: Color.white.opacity(0.16),
        specialKey: Color.white.opacity(0.07),
        keyPressed: Color.white.opacity(0.34),
        text: .white,
        secondaryText: Color.white.opacity(0.7),
        accent: rgb(0.541, 0.706, 0.973),
        accentText: rgb(0.08, 0.09, 0.11),
        shadow: Color.black.opacity(0.2),
        popup: rgb(0.27, 0.28, 0.3),
        tile: Color.white.opacity(0.14),
        chip: Color.white.opacity(0.12),
        separator: Color.white.opacity(0.2),
        solidBackground: rgb(0.16, 0.17, 0.19)
    )

    private static let lightGlass = KeyboardPalette(
        background: .clear,
        key: Color.white.opacity(0.62),
        specialKey: Color.white.opacity(0.3),
        keyPressed: Color.white.opacity(0.9),
        text: rgb(0.1, 0.1, 0.12),
        secondaryText: rgb(0.32, 0.33, 0.36),
        accent: rgb(0.102, 0.451, 0.91),
        accentText: .white,
        shadow: Color.black.opacity(0.12),
        popup: .white,
        tile: Color.white.opacity(0.6),
        chip: Color.white.opacity(0.45),
        separator: Color.black.opacity(0.1),
        solidBackground: rgb(0.9, 0.91, 0.93)
    )

    private static func gradientPalette(_ colors: [Color], dark: Bool, accent: Color) -> KeyboardPalette {
        KeyboardPalette(
            background: colors.first ?? .black,
            key: Color.white.opacity(dark ? 0.2 : 0.62),
            specialKey: Color.white.opacity(dark ? 0.1 : 0.32),
            keyPressed: Color.white.opacity(dark ? 0.38 : 0.9),
            text: dark ? .white : rgb(0.18, 0.1, 0.12),
            secondaryText: dark ? Color.white.opacity(0.7) : rgb(0.4, 0.28, 0.3),
            accent: accent,
            accentText: dark ? rgb(0.08, 0.09, 0.11) : .white,
            shadow: Color.black.opacity(dark ? 0.25 : 0.12),
            popup: dark ? rgb(0.25, 0.25, 0.3) : .white,
            tile: Color.white.opacity(dark ? 0.16 : 0.6),
            chip: Color.white.opacity(dark ? 0.12 : 0.45),
            separator: dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
            gradient: colors
        )
    }

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
