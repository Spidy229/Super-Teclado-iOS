import SwiftUI

private struct KeyboardPaletteKey: EnvironmentKey {
    static let defaultValue = KeyboardPalette.make(theme: .dark, systemIsDark: true)
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
