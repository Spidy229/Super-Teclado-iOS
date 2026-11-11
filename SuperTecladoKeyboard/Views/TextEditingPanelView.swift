import SwiftUI

struct PanelHeaderView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            PanelBackButton { engine.closePanel() }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Panel de edición de texto: mover el cursor por letras, palabras o líneas y copiar, cortar o pegar.
struct TextEditingPanelView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 4
            let columns: CGFloat = 4
            let unitWidth = (proxy.size.width - padding * 2) / columns
            let rowHeight = (proxy.size.height - padding * 2) / 3
            let size = CGSize(width: unitWidth, height: rowHeight)
            let wide = CGSize(width: unitWidth * 2, height: rowHeight)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    RepeatingKeyView(size: size, symbol: "arrow.left.to.line", title: "Inicio", accessibilityText: "Inicio de línea") {
                        engine.moveCursorToLineStart()
                    }
                    RepeatingKeyView(size: size, symbol: "chevron.left", title: nil, accessibilityText: "Izquierda") {
                        engine.moveCursor(by: -1)
                    }
                    RepeatingKeyView(size: size, symbol: "chevron.right", title: nil, accessibilityText: "Derecha") {
                        engine.moveCursor(by: 1)
                    }
                    RepeatingKeyView(size: size, symbol: "arrow.right.to.line", title: "Fin", accessibilityText: "Fin de línea") {
                        engine.moveCursorToLineEnd()
                    }
                }
                HStack(spacing: 0) {
                    RepeatingKeyView(size: wide, symbol: "chevron.left.2", title: "Palabra anterior", accessibilityText: "Palabra anterior") {
                        engine.moveCursorWordLeft()
                    }
                    RepeatingKeyView(size: wide, symbol: "chevron.right.2", title: "Palabra siguiente", accessibilityText: "Palabra siguiente") {
                        engine.moveCursorWordRight()
                    }
                }
                HStack(spacing: 0) {
                    actionKey("Copiar", symbol: "doc.on.doc", size: size) { engine.copySelection() }
                    actionKey("Cortar", symbol: "scissors", size: size) { engine.cutSelection() }
                    actionKey("Pegar", symbol: "doc.on.clipboard", size: size) { engine.pasteFromPasteboard() }
                    DeleteKeyView(size: size)
                }
            }
            .padding(padding)
        }
    }

    private func actionKey(
        _ title: String,
        symbol: String,
        size: CGSize,
        action: @escaping () -> Void
    ) -> some View {
        FunctionKeyView(size: size, accessibilityText: title, action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(palette.text)
        }
    }
}
