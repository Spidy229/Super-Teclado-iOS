import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var engine: KeyboardEngine

    var body: some View {
        let palette = KeyboardPalette.make(
            theme: engine.preferences.theme,
            systemIsDark: engine.isDark,
            custom: engine.preferences.customColors,
            glassTransparency: engine.preferences.glassTransparency
        )
        let showsFavorites = engine.metrics.favoritesRowHeight > 0 && engine.panel == .typing
        VStack(spacing: 0) {
            topStrip
                .frame(height: engine.metrics.stripHeight)
                .zIndex(0)
            if showsFavorites {
                FavoritesRowView()
                    .frame(height: engine.metrics.favoritesRowHeight)
                    .zIndex(0)
            }
            // Sin la fila de favoritos (otros paneles), el panel ocupa también su altura.
            panel
                .frame(height: engine.metrics.keyAreaHeight + (showsFavorites ? 0 : engine.metrics.favoritesRowHeight))
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // El fondo lo dibuja `KeyboardBackgroundView` (UIKit) debajo de esta vista; la barra de
        // sugerencias, las teclas y los avisos, `KeyboardViewController` (UIKit) encima.
        .environment(\.keyboardPalette, palette)
        .environment(\.colorScheme, engine.isDark ? .dark : .light)
        .environmentObject(engine)
        .animation(.easeOut(duration: 0.15), value: engine.panel)
    }

    @ViewBuilder
    private var topStrip: some View {
        switch engine.panel {
        case .typing: Color.clear
        case .clipboard: ClipboardHeaderView()
        case .emoji: EmojiHeaderView()
        case .emojiSearch: EmojiSearchBarView()
        case .clipboardSearch: ClipboardSearchBarView()
        case .editing: PanelHeaderView(title: "Edición de texto")
        case .themes: PanelHeaderView(title: "Temas")
        case .settings: PanelHeaderView(title: "Ajustes")
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch engine.panel {
        case .typing: TypingKeyboardView()
        case .clipboard: ClipboardPanelView()
        case .emoji: EmojiPanelView()
        case .emojiSearch: TypingKeyboardView()
        case .clipboardSearch:
            VStack(spacing: 0) {
                ClipboardSearchResultsView().frame(height: 50)
                TypingKeyboardView()
            }
        case .editing: TextEditingPanelView()
        case .themes: ThemePickerPanelView()
        case .settings: KeyboardSettingsPanelView()
        }
    }
}
