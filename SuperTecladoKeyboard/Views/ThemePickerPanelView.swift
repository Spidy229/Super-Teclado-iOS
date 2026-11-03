import SwiftUI

/// Selector de temas dentro del teclado: un toque cambia el tema al momento.
struct ThemePickerPanelView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    private var options: [KeyboardThemeOption] {
        KeyboardThemeOption.allCases.filter { $0 != .photo || KeyboardBackgroundStore.hasImage }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 10) {
                    ForEach(options) { option in
                        Button {
                            engine.keyFeedback(.character)
                            engine.setTheme(option)
                        } label: {
                            VStack(spacing: 4) {
                                KeyboardThemePreview(
                                    option: option,
                                    systemIsDark: engine.isDark,
                                    custom: engine.preferences.customColors,
                                    photo: engine.backgroundImage,
                                    dim: engine.preferences.backgroundDim
                                )
                                .frame(height: 58)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            engine.preferences.theme == option ? palette.accent : palette.separator,
                                            lineWidth: engine.preferences.theme == option ? 3 : 1
                                        )
                                }
                                Text(option.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(engine.preferences.theme == option ? palette.accent : palette.text)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(engine.preferences.theme == option ? .isSelected : [])
                    }
                }
                .padding(10)
            }

            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { engine.preferences.keyBorders },
                    set: { engine.setKeyBorders($0) }
                )) {
                    Text("Bordes de las teclas")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.text)
                }
                .tint(palette.accent)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(palette.specialKey.opacity(0.55))

            Text("Colores propios y foto de fondo: app Super Teclado › Ajustes del teclado › Tema")
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(height: 20)
        }
    }
}
