import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var engine: KeyboardEngine

    var body: some View {
        let palette = KeyboardPalette.make(
            theme: engine.preferences.theme,
            systemIsDark: engine.isDark,
            custom: engine.preferences.customColors
        )
        VStack(spacing: 0) {
            topStrip
                .frame(height: engine.metrics.stripHeight)
                .zIndex(0)
            panel
                .frame(height: engine.metrics.keyAreaHeight)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { background(palette: palette) }
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
        case .emojiSearch: EmojiSearchBarView()
        case .clipboardSearch: ClipboardSearchBarView()
        case .editing: PanelHeaderView(title: "Edición de texto")
        case .themes: PanelHeaderView(title: "Temas")
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
        }
    }

    @ViewBuilder
    private func background(palette: KeyboardPalette) -> some View {
        if engine.preferences.theme == .photo, let image = engine.backgroundImage {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay(Color.black.opacity(engine.preferences.backgroundDim))
            }
        } else {
            palette.background
        }
    }

    @ViewBuilder
    private func toast(palette: KeyboardPalette) -> some View {
        if let message = engine.toast {
            HStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                if let actionTitle = engine.toastActionTitle {
                    Button(actionTitle) { engine.performToastAction() }
                        .font(.system(size: 13, weight: .bold))
                        .underline()
                        .buttonStyle(.plain)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.accent, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .padding(.top, engine.metrics.stripHeight + 6)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .allowsHitTesting(engine.toastActionTitle != nil)
        }
    }
}
