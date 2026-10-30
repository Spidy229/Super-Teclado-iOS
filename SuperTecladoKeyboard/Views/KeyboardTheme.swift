import SwiftUI

/// Colores inspirados en los temas claro y oscuro de Gboard.
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

    static func make(dark: Bool) -> KeyboardPalette {
        if dark {
            return KeyboardPalette(
                background: Color(red: 0.125, green: 0.129, blue: 0.141),
                key: Color(red: 0.275, green: 0.282, blue: 0.298),
                specialKey: Color(red: 0.2, green: 0.208, blue: 0.22),
                keyPressed: Color(red: 0.38, green: 0.39, blue: 0.41),
                text: Color(red: 0.91, green: 0.918, blue: 0.929),
                secondaryText: Color(red: 0.6, green: 0.62, blue: 0.64),
                accent: Color(red: 0.541, green: 0.706, blue: 0.973),
                accentText: Color(red: 0.11, green: 0.12, blue: 0.14),
                shadow: Color.black.opacity(0.45),
                popup: Color(red: 0.33, green: 0.34, blue: 0.36),
                tile: Color(red: 0.235, green: 0.243, blue: 0.259),
                chip: Color(red: 0.2, green: 0.208, blue: 0.22),
                separator: Color.white.opacity(0.14)
            )
        }
        return KeyboardPalette(
            background: Color(red: 0.91, green: 0.918, blue: 0.933),
            key: .white,
            specialKey: Color(red: 0.792, green: 0.808, blue: 0.835),
            keyPressed: Color(red: 0.72, green: 0.74, blue: 0.77),
            text: Color(red: 0.125, green: 0.129, blue: 0.141),
            secondaryText: Color(red: 0.37, green: 0.39, blue: 0.41),
            accent: Color(red: 0.102, green: 0.451, blue: 0.91),
            accentText: .white,
            shadow: Color.black.opacity(0.22),
            popup: .white,
            tile: .white,
            chip: Color(red: 0.84, green: 0.855, blue: 0.875),
            separator: Color.black.opacity(0.12)
        )
    }
}

private struct KeyboardPaletteKey: EnvironmentKey {
    static let defaultValue = KeyboardPalette.make(dark: true)
}

extension EnvironmentValues {
    var keyboardPalette: KeyboardPalette {
        get { self[KeyboardPaletteKey.self] }
        set { self[KeyboardPaletteKey.self] = newValue }
    }
}

/// Fondo de una tecla con la separación y la sombra inferior típicas de Gboard.
struct KeyCapView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let fill: Color
    var isPressed = false
    var alwaysFilled = false

    var body: some View {
        let showsBorder = engine.preferences.keyBorders || alwaysFilled
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isPressed ? palette.keyPressed : (showsBorder ? fill : Color.clear))
            .shadow(color: showsBorder ? palette.shadow : .clear, radius: 0, x: 0, y: 1)
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
    }
}

/// Botón de la barra superior (herramientas, cabeceras de paneles).
struct StripButton: View {
    @Environment(\.keyboardPalette) private var palette
    let symbol: String
    var isActive = false
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isActive ? palette.accent : palette.text.opacity(0.85))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? symbol)
    }
}
