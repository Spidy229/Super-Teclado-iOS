import SwiftUI
import UIKit

/// Bienvenida paso a paso: qué ofrece el teclado, cómo activarlo y una prueba final.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @State private var testText = ""
    @State private var keyboardDetected = false

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Saltar") { finish() }
                    .opacity(page < pageCount - 1 ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            TabView(selection: $page) {
                welcomePage.tag(0)
                addKeyboardPage.tag(1)
                fullAccessPage.tag(2)
                tryItPage.tag(3)
                tipsPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < pageCount - 1 ? "Siguiente" : "Empezar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
    }

    // MARK: Páginas

    private var welcomePage: some View {
        onboardingPage(
            symbol: "keyboard.fill",
            title: "Bienvenido a Super Teclado",
            text: "Un teclado al estilo Gboard para tu iPhone."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature("scribble", "Escritura deslizando, sugerencias y autocorrección")
                feature("doc.on.clipboard", "Portapapeles con historial, fijados y búsqueda")
                feature("face.smiling", "Emojis con búsqueda y tonos de piel")
                feature("paintpalette", "Temas, colores propios y foto de fondo")
                feature("globe", "Español, catalán, portugués, inglés, francés, italiano y alemán")
            }
        }
    }

    private var addKeyboardPage: some View {
        onboardingPage(
            symbol: "plus.rectangle.on.rectangle",
            title: "Añade el teclado",
            text: "Abre los ajustes de Super Teclado y activa el teclado."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                stepRow(1, "Toca «Abrir Ajustes».")
                stepRow(2, "Entra en «Teclados».")
                stepRow(3, "Activa «Super Teclado».")
                openSettingsButton
            }
        }
    }

    private var fullAccessPage: some View {
        onboardingPage(
            symbol: "lock.open.fill",
            title: "Permite el acceso total",
            text: "En la misma pantalla, activa «Permitir acceso total»."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature("doc.on.clipboard", "Lo necesita el portapapeles para guardar lo que copias")
                feature("iphone.radiowaves.left.and.right", "Y la vibración de las teclas")
                feature("lock.shield", "Lo que escribes no sale de tu iPhone: el teclado no usa internet")
                openSettingsButton
            }
        }
    }

    private var tryItPage: some View {
        onboardingPage(
            symbol: keyboardDetected ? "checkmark.seal.fill" : "hand.point.up.left.fill",
            title: "Pruébalo",
            text: "Toca el campo, mantén pulsado 🌐 y elige Super Teclado."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Escribe aquí", text: $testText, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                Label(
                    keyboardDetected ? "¡Listo! El teclado funciona con acceso total." : "Aún no se ha detectado el teclado con acceso total.",
                    systemImage: keyboardDetected ? "checkmark.circle.fill" : "clock"
                )
                .font(.subheadline)
                .foregroundStyle(keyboardDetected ? .green : .secondary)
            }
        }
    }

    private var tipsPage: some View {
        onboardingPage(
            symbol: "sparkles",
            title: "Trucos",
            text: "Lo esencial para sacarle partido."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature("scribble", "Desliza de letra en letra para escribir sin levantar el dedo")
                feature("arrow.left.and.right", "Desliza sobre el espacio para mover el cursor")
                feature("hand.tap", "Mantén una tecla para ver acentos y símbolos")
                feature("clipboard", "El icono del portapapeles abre tu historial")
                feature("paintpalette", "La paleta cambia el tema al momento")
            }
        }
    }

    // MARK: Piezas

    private func onboardingPage<Content: View>(
        symbol: String,
        title: String,
        text: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(.cyan.gradient)
                    .padding(.top, 24)
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                content()
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 50)
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.cyan)
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.cyan, in: Circle())
            Text(text)
        }
    }

    private var openSettingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Label("Abrir Ajustes", systemImage: "gear")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(.cyan)
        .padding(.top, 6)
    }

    private func refreshStatus() {
        let value = SharedClipboardStore.sharedDefaults?.double(forKey: KeyboardPreferenceKey.lastActive) ?? 0
        keyboardDetected = value > 0
    }

    private func finish() {
        hasCompletedOnboarding = true
        dismiss()
    }
}
