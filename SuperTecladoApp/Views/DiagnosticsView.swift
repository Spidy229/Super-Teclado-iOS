import SwiftUI
import UIKit

/// Cómo está funcionando el teclado en este iPhone, con un informe para copiar y enviar.
struct DiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var diagnostics = KeyboardDiagnostics()
    @State private var lastActive: Date?
    @State private var copied = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                KeyboardStatusView()
            }

            Section {
                LabeledContent("Memoria disponible", value: megabytes(diagnostics.availableMemoryMB))
                LabeledContent("Mínima registrada", value: megabytes(diagnostics.lowestAvailableMemoryMB))
                memoryVerdict
            } header: {
                Text("Memoria del teclado")
            } footer: {
                Text("iOS cierra los teclados que se quedan sin memoria y vuelve al teclado del sistema. Por debajo de 10 MB conviene usar un solo idioma o desactivar la foto de fondo.")
            }

            Section("Diccionario") {
                LabeledContent("Idiomas", value: diagnostics.languages?.replacingOccurrences(of: "+", with: " + ") ?? "Sin datos")
                LabeledContent("Palabras", value: diagnostics.dictionaryWordCount.map { $0.formatted() } ?? "Sin datos")
                LabeledContent("Tiempo de carga", value: diagnostics.dictionaryLoadMilliseconds.map { "\($0) ms" } ?? "Sin datos")
            }

            Section {
                LabeledContent("Cierres inesperados", value: "\(diagnostics.unexpectedExits)")
                LabeledContent("Seguidos", value: "\(diagnostics.consecutiveUnexpectedExits)")
                if diagnostics.isSafeModeActive {
                    Label("Modo seguro activo: el teclado arranca sin sugerencias", systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(.orange)
                }
                if let date = diagnostics.lastUnexpectedExit {
                    LabeledContent("Último", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            } header: {
                Text("Estabilidad")
            } footer: {
                Text("Se cuenta cuando el teclado deja de funcionar mientras estaba en pantalla. Tras dos cierres seguidos arranca en modo seguro (sin diccionarios) para que puedas seguir escribiendo; «Reiniciar contadores» lo desactiva.")
            }

            Section {
                let freezes = MainThreadWatchdog.shared.freezes
                if freezes.isEmpty {
                    Text("Ninguna desde que se abrió la app")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(freezes.enumerated()), id: \.offset) { _, freeze in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.0f ms a los %.0f s", freeze.milliseconds, freeze.secondsSinceStart))
                            .font(.subheadline.weight(.semibold))
                        Text(MainThreadWatchdog.culprit(of: freeze))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Congelaciones de la app")
            } footer: {
                Text("Si la app deja de responder más de una décima de segundo, aquí sale qué función la tenía ocupada. Van también en el informe.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = diagnostics.report(appVersion: appVersion, lastActive: lastActive)
                        + "\n" + MainThreadWatchdog.shared.report
                    copied = true
                } label: {
                    Label(copied ? "Informe copiado" : "Copiar informe", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button("Reiniciar contadores", role: .destructive) {
                    KeyboardDiagnostics.reset()
                    reload()
                }
            }
        }
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    @ViewBuilder
    private var memoryVerdict: some View {
        if let lowest = diagnostics.lowestAvailableMemoryMB {
            if lowest < 10 {
                Label("Va justo de memoria", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Label("Memoria suficiente", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else {
            Label("Abre el teclado en cualquier app para obtener datos", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func megabytes(_ value: Double?) -> String {
        value.map { String(format: "%.0f MB", $0) } ?? "Sin datos"
    }

    private func reload() {
        diagnostics = KeyboardDiagnostics.load()
        let value = SharedClipboardStore.sharedDefaults?.double(forKey: KeyboardPreferenceKey.lastActive) ?? 0
        lastActive = value > 0 ? Date(timeIntervalSince1970: value) : nil
        copied = false
    }
}
