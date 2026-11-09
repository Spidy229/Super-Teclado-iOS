import SwiftUI

/// Retraso de la pulsación larga que se elige en el panel del teclado.
private enum LongPressOption: Int, CaseIterable, Hashable {
    case short = 250
    case normal = 400
    case long = 550

    init(milliseconds: Int) {
        self = Self.allCases.min { abs($0.rawValue - milliseconds) < abs($1.rawValue - milliseconds) } ?? .normal
    }

    var milliseconds: Int { rawValue }

    var title: String {
        switch self {
        case .short: "Corta"
        case .normal: "Normal"
        case .long: "Larga"
        }
    }
}

/// Ajustes rápidos dentro del teclado. Se guardan aunque la app y el teclado no compartan
/// datos (cuando la firma no incluye el App Group), y muestra el estado del acceso total.
struct KeyboardSettingsPanelView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    @State private var strength = 0.6
    @State private var diagnostics = TouchDiagnostics()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusSection
                vibrationSection
                soundSection
                writingSection
                diagnosticsSection
            }
            .padding(12)
        }
        .onAppear {
            strength = engine.preferences.hapticsStrength
            diagnostics = engine.touchDiagnostics
        }
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
            // Resumen de la velocidad, a la vista sin bajar hasta el diagnóstico.
            if !diagnostics.delivery.isEmpty {
                Text("Velocidad · iOS \(TouchDiagnostics.summary(diagnostics.delivery)) · teclado \(TouchDiagnostics.summary(diagnostics.handling)) · bloqueos \(diagnostics.stalls)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InstantButton {
                engine.copyDiagnosticsReport()
            } label: {
                Label("Copiar informe de velocidad", systemImage: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
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
            toggleRow("Espacio tras elegir una sugerencia", isOn: engine.preferences.spaceAfterSuggestion) { value in
                engine.updatePreferences { $0.spaceAfterSuggestion = value }
            }
            toggleRow("Precisión inteligente", isOn: engine.preferences.smartTouch) { value in
                engine.updatePreferences { $0.smartTouch = value }
            }
            Text("Si tocas justo entre dos letras, elige la que forma una palabra, como el teclado de Apple.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pulsación larga (acentos y símbolos)")
                .font(.system(size: 13))
                .foregroundStyle(palette.text)
            chips(LongPressOption.allCases, selected: LongPressOption(milliseconds: engine.preferences.longPressDelay), title: \.title) { option in
                engine.updatePreferences { $0.longPressDelay = option.milliseconds }
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

    // MARK: Diagnóstico

    private var diagnosticsSection: some View {
        section("Diagnóstico de toques") {
            toggleRow("Mostrar velocidad en la barra", isOn: engine.preferences.showSpeed) { value in
                engine.updatePreferences { $0.showSpeed = value }
            }
            VStack(alignment: .leading, spacing: 4) {
                timingRow("Retraso de iOS al entregar el toque", TouchDiagnostics.summary(diagnostics.delivery))
                timingRow("Tiempo del teclado por toque", TouchDiagnostics.summary(diagnostics.handling))
                timingRow("Vibración (lo que tarda iOS en aceptarla)", TouchDiagnostics.summary(diagnostics.feedback))
                timingRow("Retraso del hilo principal", TouchDiagnostics.summary(diagnostics.lateness))
                timingRow(
                    "Bloqueos de más de 100 ms",
                    diagnostics.stalls == 0 ? "0" : String(format: "%d · el mayor %.0f ms", diagnostics.stalls, diagnostics.longestStall)
                )
                diagnosticRow("Toques", diagnostics.touches)
                diagnosticRow("Escritos", diagnostics.typed)
                diagnosticRow("Escritos al tocar con otro dedo", diagnostics.rollovers)
                diagnosticRow("Cancelados por iOS y escritos", diagnostics.cancelledTyped)
                diagnosticRow("Cancelados por iOS y perdidos", diagnostics.cancelledLost)
                diagnosticRow("Sin aviso de fin (escritos)", diagnostics.unfinished)
                diagnosticRow("Ignorados (deslizando o dedo apoyado)", diagnostics.ignored)
                diagnosticRow("Deslizamientos", diagnostics.glides)
                diagnosticRow("Deslizamientos que eran toques", diagnostics.glidesAsTaps)
                diagnosticRow("Cursor con la barra espaciadora", diagnostics.cursorSwipes)
                diagnosticRow("Pulsaciones largas", diagnostics.alternates)
                diagnosticRow("Elegidos por la precisión inteligente", diagnostics.smartChoices)
            }
            if !diagnostics.recent.isEmpty {
                Text("Últimos toques")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Text(diagnostics.recent.joined(separator: "\n"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InstantButton("Poner a cero") {
                engine.touchDiagnostics = TouchDiagnostics()
                diagnostics = TouchDiagnostics()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(palette.accent)
            .buttonStyle(.plain)
            Text("Si notas que falla una tecla, abre esto justo después y pulsa «Copiar informe de velocidad» (arriba): pégalo en tu mensaje.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func timingRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(value).monospacedDigit().foregroundStyle(palette.accent)
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.text)
    }

    private func diagnosticRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text("\(value)").monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.text)
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
                    InstantButton { onSelect(option) } label: {
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
