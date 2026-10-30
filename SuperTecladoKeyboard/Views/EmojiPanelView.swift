import SwiftUI

struct EmojiHeaderView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            StripButton(symbol: "arrow.left", label: "Volver al teclado") { engine.closePanel() }
            Text("Emojis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
            StripButton(symbol: "clipboard", label: "Portapapeles") { engine.open(.clipboard) }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmojiPanelView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    @State private var selectedCategory = ""

    private var categories: [EmojiCategory] {
        var result: [EmojiCategory] = []
        if !engine.recentEmojis.isEmpty {
            result.append(EmojiCategory(id: "recent", title: "Recientes", symbol: "clock", emojis: engine.recentEmojis))
        }
        result += EmojiCatalog.categories
        return result
    }

    var body: some View {
        let sections = categories
        ScrollViewReader { reader in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { category in
                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .id(category.id)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 0)], spacing: 0) {
                                ForEach(Array(category.emojis.enumerated()), id: \.offset) { _, emoji in
                                    Button {
                                        engine.keyFeedback(.character)
                                        engine.insertEmoji(emoji)
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 30))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(EmojiButtonStyle())
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.bottom, 6)
                }

                categoryBar(sections: sections, reader: reader)
            }
        }
    }

    private func categoryBar(sections: [EmojiCategory], reader: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            Button { engine.closePanel() } label: {
                Text("ABC")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 48, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.text)

            ForEach(sections) { category in
                Button {
                    selectedCategory = category.id
                    withAnimation(.easeOut(duration: 0.2)) {
                        reader.scrollTo(category.id, anchor: .top)
                    }
                } label: {
                    Image(systemName: category.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(selectedCategory == category.id ? palette.accent : palette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.title)
            }

            DeleteKeyView(size: CGSize(width: 52, height: 40), fill: .clear)
        }
        .padding(.horizontal, 4)
        .frame(height: 42)
        .background(palette.specialKey.opacity(0.55))
    }
}

private struct EmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.25 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
