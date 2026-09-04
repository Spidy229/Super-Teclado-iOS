import SwiftUI

struct LockView: View {
    @ObservedObject var controller: AppLockController

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(.cyan.gradient)

            VStack(spacing: 8) {
                Text("Historial protegido")
                    .font(.title.bold())
                Text("Usa Face ID para abrir Super Teclado.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let error = controller.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await controller.unlock() }
            } label: {
                Label("Desbloquear", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)

            Spacer()
        }
        .padding(32)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.18), .cyan.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

