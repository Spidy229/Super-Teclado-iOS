import SwiftUI

struct TypingKeyboardView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let mode = engine.preferences.oneHandedMode
            let sideWidth: CGFloat = mode == .off ? 0 : min(72, proxy.size.width * 0.17)
            HStack(spacing: 0) {
                if mode == .right { oneHandedPanel(width: sideWidth, height: proxy.size.height) }
                // Hueco de las teclas: las dibuja `KeyGridUIView` (UIKit) encima de esta vista.
                Color.clear
                    .frame(width: proxy.size.width - sideWidth, height: proxy.size.height)
                if mode == .left { oneHandedPanel(width: sideWidth, height: proxy.size.height) }
            }
        }
    }

    private func oneHandedPanel(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 18) {
            InstantButton { engine.setOneHandedMode(.off) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: width, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Salir del modo una mano")
            InstantButton {
                engine.setOneHandedMode(engine.preferences.oneHandedMode == .right ? .left : .right)
            } label: {
                Image(systemName: engine.preferences.oneHandedMode == .right ? "chevron.right" : "chevron.left")
                    .frame(width: width, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Cambiar de lado")
        }
        .buttonStyle(.plain)
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(palette.text.opacity(0.8))
        .frame(width: width, height: height)
    }
}
