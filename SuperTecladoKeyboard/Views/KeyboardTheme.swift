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
        // La sombra se dibuja como una segunda forma desplazada: `.shadow` obliga a renderizar
        // cada tecla fuera de pantalla y hacía el teclado más lento.
        ZStack {
            if showsBorder {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.shadow)
                    .offset(y: 1)
            }
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPressed ? palette.keyPressed : (showsBorder ? fill : Color.clear))
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
    }
}

/// Botón para volver al teclado desde los paneles. Es ancho y está separado del borde de la
/// pantalla, porque iOS retrasa o descarta los toques pegados al borde por sus propios gestos.
struct PanelBackButton: View {
    @Environment(\.keyboardPalette) private var palette
    var title = "ABC"
    let action: () -> Void

    var body: some View {
        InstantButton(feedback: .modifier, action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .frame(minWidth: 72, minHeight: 34)
            .background(palette.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .padding(.leading, 6)
        .accessibilityLabel("Volver")
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
        InstantButton(feedback: .modifier, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isActive ? palette.accent : palette.text.opacity(0.85))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label ?? symbol)
    }
}
