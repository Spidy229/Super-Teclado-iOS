import SwiftUI

/// Barra superior: sugerencias mientras se escribe y herramientas (emoji, portapapeles…) en reposo.
struct SuggestionStripView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        let quickPaste = engine.currentWord.isEmpty ? engine.quickPaste : nil
        let hasContent = engine.hasSuggestions || quickPaste != nil
        HStack(spacing: 0) {
            if hasContent {
                StripButton(
                    symbol: engine.showsToolbar ? "chevron.left" : "square.grid.2x2",
                    label: engine.showsToolbar ? "Ver sugerencias" : "Ver herramientas"
                ) {
                    engine.showsToolbar.toggle()
                }
            }

            if engine.showsToolbar || !hasContent {
                toolbarIcons(compact: false)
            } else if let quickPaste {
                // Lo recién copiado tiene prioridad sobre la predicción de la siguiente palabra.
                quickPasteChip(quickPaste)
                Spacer(minLength: 4)
                toolbarIcons(compact: true)
            } else {
                suggestionsRow
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(engine.suggestions.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(palette.separator)
                        .frame(width: 1, height: 20)
                }
                Button {
                    if let item { engine.selectSuggestion(item) }
                } label: {
                    Text(item.map { title(for: $0) } ?? "")
                        .font(.system(
                            size: item?.kind == .emoji ? 22 : 17,
                            weight: item?.kind == .correction ? .semibold : .regular
                        ))
                        .foregroundStyle(item?.kind == .correction ? palette.accent : palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item == nil)
            }
        }
    }

    private func title(for item: SuggestionItem) -> String {
        let hasCorrection = engine.suggestions.contains { $0?.kind == .correction }
        return item.kind == .typed && hasCorrection ? "«\(item.text)»" : item.text
    }

    private func quickPasteChip(_ clip: KeyboardClip) -> some View {
        Button { engine.useQuickPaste() } label: {
            HStack(spacing: 7) {
                if let fileName = clip.imageFileName {
                    ClipThumbnailView(fileName: fileName)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("Imagen copiada")
                } else {
                    Image(systemName: "doc.on.clipboard")
                    Text(clip.text.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: 230, minHeight: 32)
            .background(palette.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pegar lo último copiado")
    }

    @ViewBuilder
    private func toolbarIcons(compact: Bool) -> some View {
        if compact {
            StripButton(symbol: "clipboard", label: "Portapapeles") { engine.open(.clipboard) }
            StripButton(symbol: "keyboard.chevron.compact.down", label: "Ocultar teclado") { engine.dismissKeyboard() }
        } else {
            HStack(spacing: 0) {
                StripButton(symbol: "face.smiling", label: "Emojis") { engine.open(.emoji) }
                Spacer(minLength: 0)
                StripButton(symbol: "clipboard", label: "Portapapeles") { engine.open(.clipboard) }
                Spacer(minLength: 0)
                StripButton(symbol: "character.cursor.ibeam", label: "Edición de texto") { engine.open(.editing) }
                Spacer(minLength: 0)
                StripButton(
                    symbol: "hand.point.up.left",
                    isActive: engine.preferences.oneHandedMode != .off,
                    label: "Modo una mano"
                ) {
                    engine.toggleOneHandedMode()
                }
                Spacer(minLength: 0)
                StripButton(symbol: "paintpalette", label: "Tema") { engine.cycleTheme() }
                Spacer(minLength: 0)
                StripButton(symbol: "keyboard.chevron.compact.down", label: "Ocultar teclado") { engine.dismissKeyboard() }
            }
        }
    }
}
