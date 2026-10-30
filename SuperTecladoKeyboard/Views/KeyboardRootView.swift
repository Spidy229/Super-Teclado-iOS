import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var engine: KeyboardEngine

    var body: some View {
        let palette = KeyboardPalette.make(dark: engine.isDark)
        VStack(spacing: 0) {
            topStrip
                .frame(height: engine.metrics.stripHeight)
                .zIndex(0)
            panel
                .frame(height: engine.metrics.keyAreaHeight)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.background)
        .overlay(alignment: .top) { toast(palette: palette) }
        .environment(\.keyboardPalette, palette)
        .environment(\.colorScheme, engine.isDark ? .dark : .light)
        .environmentObject(engine)
        .animation(.easeOut(duration: 0.15), value: engine.panel)
    }

    @ViewBuilder
    private var topStrip: some View {
        switch engine.panel {
        case .typing: SuggestionStripView()
        case .clipboard: ClipboardHeaderView()
        case .emoji: EmojiHeaderView()
        case .editing: PanelHeaderView(title: "Edición de texto")
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch engine.panel {
        case .typing: TypingKeyboardView()
        case .clipboard: ClipboardPanelView()
        case .emoji: EmojiPanelView()
        case .editing: TextEditingPanelView()
        }
    }

    @ViewBuilder
    private func toast(palette: KeyboardPalette) -> some View {
        if let message = engine.toast {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.accent, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .padding(.top, engine.metrics.stripHeight + 6)
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
        }
    }
}
