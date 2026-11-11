import SwiftUI

struct EmojiHeaderView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            PanelBackButton { engine.closePanel() }
            InstantButton { engine.openEmojiSearch() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Buscar emojis")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 15))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(palette.chip, in: Capsule())
            }
            .buttonStyle(.plain)
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
    @State private var toneEmoji: String?

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
                                    emojiCell(emoji)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.bottom, 6)
                }

                categoryBar(sections: sections, reader: reader)
            }
            .overlay(alignment: .top) {
                if let toneEmoji { tonePicker(for: toneEmoji) }
            }
        }
    }

    /// Toca para insertar; mantén pulsado en personas y manos para elegir el tono de piel.
    private func emojiCell(_ emoji: String) -> some View {
        let shown = engine.preferredVariant(of: emoji)
        return Text(shown)
            .font(.system(size: 30))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(alignment: .bottomTrailing) {
                if EmojiSkinTone.supportsTones(emoji) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(palette.secondaryText)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            // Reconocedor de UIKit (en iOS 27 los toques de SwiftUI se retrasan); si el dedo se
            // desplaza, deja desplazar la lista de emojis.
            .gesture(
                InstantTouchGesture(
                    longPressDuration: EmojiSkinTone.supportsTones(emoji) ? 0.35 : nil,
                    onTap: {
                        engine.keyFeedback(.character)
                        engine.insertEmoji(shown)
                    },
                    onLongPress: {
                        engine.keyFeedback(.modifier)
                        toneEmoji = emoji
                    }
                )
            )
            .accessibilityLabel(shown)
            .accessibilityAddTraits(.isButton)
    }

    private func tonePicker(for emoji: String) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .gesture(InstantTouchGesture(onTap: { toneEmoji = nil }))
            HStack(spacing: 2) {
                ForEach(EmojiSkinTone.variants(of: emoji), id: \.self) { variant in
                    InstantButton {
                        engine.setPreferredVariant(variant, for: emoji)
                        engine.keyFeedback(.character)
                        engine.insertEmoji(variant)
                        toneEmoji = nil
                    } label: {
                        Text(variant)
                            .font(.system(size: 32))
                            .frame(width: 46, height: 50)
                            .background(
                                engine.preferredVariant(of: emoji) == variant ? palette.chip : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(EmojiButtonStyle())
                }
            }
            .padding(6)
            .background(palette.popup, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .padding(.top, 10)
        }
        .transition(.opacity)
    }

    private func categoryBar(sections: [EmojiCategory], reader: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            InstantButton { engine.closePanel() } label: {
                Text("ABC")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 48, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.text)

            ForEach(sections) { category in
                InstantButton {
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

/// Barra de búsqueda de emojis: lo que se escribe con el teclado va al buscador.
struct EmojiSearchBarView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            PanelBackButton(title: "😀") { engine.open(.emoji) }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryText)
                Text(engine.searchQuery.isEmpty ? "Buscar emojis" : engine.searchQuery)
                    .foregroundStyle(engine.searchQuery.isEmpty ? palette.secondaryText : palette.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.accent)
                    .frame(width: 2, height: 18)
                Spacer(minLength: 0)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 10)
            .frame(width: 140, height: 32)
            .background(palette.chip, in: Capsule())

            if engine.emojiSearchResults.isEmpty {
                Text(engine.searchQuery.isEmpty ? "" : "Sin resultados")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(engine.emojiSearchResults.enumerated()), id: \.offset) { _, emoji in
                            InstantButton { engine.insertSearchedEmoji(emoji) } label: {
                                Text(engine.preferredVariant(of: emoji))
                                    .font(.system(size: 26))
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(EmojiButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
