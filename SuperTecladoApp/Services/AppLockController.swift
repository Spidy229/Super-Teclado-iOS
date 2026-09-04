import Foundation
import LocalAuthentication

@MainActor
final class AppLockController: ObservableObject {
    @Published var isLocked = true
    @Published var errorMessage: String?

    func lock() {
        isLocked = true
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = "La autenticación del dispositivo no está disponible."
            isLocked = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Desbloquea tu historial privado"
            )
            if success {
                isLocked = false
                errorMessage = nil
            }
        } catch {
            errorMessage = "No se pudo verificar tu identidad."
        }
    }
}
