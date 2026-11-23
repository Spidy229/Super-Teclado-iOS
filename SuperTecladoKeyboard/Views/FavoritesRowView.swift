import SwiftUI

/// Fila de emojis y símbolos favoritos encima de las teclas.
struct FavoritesRowView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    private var items: [String] {
        let favorites = engine.preferences.favoriteItems
        return favorites.isEmpty ? Array(engine.recentEmojis.prefix(16)) : favorites
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    InstantButton {
                        engine.keyFeedback(.character)
                        engine.insertFavorite(item)
                    } label: {
                        Text(item)
                            .font(.system(size: item.unicodeScalars.contains { $0.value >= 0x2190 } ? 24 : 19))
                            .foregroundStyle(palette.text)
                            .frame(minWidth: 38, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                }
            }
            .padding(.horizontal, 6)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }
}
