import SwiftUI

/// Ajustes rápidos dentro del teclado. Se guardan aunque la app y el teclado no compartan
/// datos (cuando la firma no incluye el App Group), y muestra el estado del acceso total.
struct KeyboardSettingsPanelView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    @State private var strength = 0.6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusSection
                vibrationSection
                soundSection
                writingSection
            }
            .padding(12)
        }
        .onAppear { strength = engine.preferences.hapticsStrength }
    }

    // MARK: Estado

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(
                engine.hasFullAccess,
                ok: "Acceso total activado",
                missing: "Sin acceso total: actívalo en Ajustes › General › Teclado › Teclados › Super Teclado"
            )
            statusRow(
                SharedClipboardStore.isAppGroupAvailable,
                ok: "Conectado con la app",
                missing: "La firma no incluye el App Group: la app no puede cambiar estos ajustes. Cámbialos aquí."
            )
            if engine.safeMode {
                statusRow(false, ok: "", missing: "Modo seguro: sin sugerencias tras varios cierres")
            }
        }
        .padding(10)
        .background(palette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusRow(_ isOK: Bool, ok: String, missing: String) -> some View {
        Label {
            Text(isOK ? ok : missing)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isOK ? Color.green : Color.orange)
        }
    }

    // MARK: Vibración

    private var vibrationSection: some View {
        section("Vibración") {
            toggleRow("Vibrar al pulsar", isOn: engine.preferences.haptics) { value in
                engine.updatePreferences { $0.haptics = value }
                if value { engine.previewHaptic() }
            }
            if engine.preferences.haptics {
                chips(HapticStyleOption.allCases, selected: engine.preferences.hapticsStyle, title: \.title) { style in
                    engine.updatePreferences { $0.hapticsStyle = style }
                    engine.previewHaptic()
                }
                HStack(spacing: 10) {
                    Text("Intensidad")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.text)
                    Slider(value: $strength, in: 0.1...1, step: 0.05) { editing in
                        guard !editing else { return }
                        engine.updatePreferences { $0.hapticsStrength = strength }
                        engine.previewHaptic()
                    }
                    .tint(palette.accent)
                    Text("\(Int((strength * 100).rounded())) %")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Sonido

    private var soundSection: some View {
        section("Sonido") {
            toggleRow("Sonido al pulsar", isOn: engine.preferences.sound) { value in
                engine.updatePreferences { $0.sound = value }
            }
            if engine.preferences.sound {
                chips(KeySoundStyle.allCases, selected: engine.preferences.soundStyle, title: \.title) { style in
                    engine.updatePreferences { $0.soundStyle = style }
                    engine.keyFeedback(.character)
                }
            }
        }
    }

    // MARK: Escritura

    private var writingSection: some View {
        section("Escritura") {
            toggleRow("Escritura deslizando", isOn: engine.preferences.glideTyping) { value in
                engine.updatePreferences { $0.glideTyping = value }
            }
            toggleRow("Autocorrección", isOn: engine.preferences.autocorrect) { value in
                engine.updatePreferences { $0.autocorrect = value }
            }
            toggleRow("Fila de números", isOn: engine.preferences.numberRow) { value in
                engine.updatePreferences { $0.numberRow = value }
            }
            toggleRow("Bordes de las teclas", isOn: engine.preferences.keyBorders) { value in
                engine.updatePreferences { $0.keyBorders = value }
            }
            toggleRow("Modo incógnito", isOn: engine.preferences.incognito) { value in
                engine.updatePreferences { $0.incognito = value }
            }
        }
    }

    // MARK: Piezas

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
            content()
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(palette.text)
        }
        .tint(palette.accent)
    }

    private func chips<Option: Hashable>(
        _ options: [Option],
        selected: Option,
        title: KeyPath<Option, String>,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button { onSelect(option) } label: {
                        Text(option[keyPath: title])
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(option == selected ? palette.accentText : palette.text)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(option == selected ? palette.accent : palette.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
