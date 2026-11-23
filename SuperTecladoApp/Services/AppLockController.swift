import Combine
import Foundation
import LocalAuthentication

@MainActor
protocol AppAuthenticating {
    func canAuthenticate() -> Bool
    func authenticate() async throws -> Bool
}

@MainActor
private struct DeviceOwnerAuthenticator: AppAuthenticating {
    private let context = LAContext()

    func canAuthenticate() -> Bool {
        context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Desbloquea tu historial privado"
            ) { @Sendable success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

@MainActor
final class AppLockController: ObservableObject {
    @Published var isLocked = true
    @Published var errorMessage: String?
    private let makeAuthenticator: @MainActor () -> any AppAuthenticating

    init() {
        self.makeAuthenticator = { DeviceOwnerAuthenticator() }
    }

    init(makeAuthenticator: @escaping @MainActor () -> any AppAuthenticating) {
        self.makeAuthenticator = makeAuthenticator
    }

    func lock() {
        isLocked = true
    }

    func unlock() async {
        isLocked = true
        let authenticator = makeAuthenticator()

        guard authenticator.canAuthenticate() else {
            errorMessage = "Configura un código de desbloqueo en los ajustes del dispositivo para abrir el historial protegido."
            return
        }

        do {
            let success = try await authenticator.authenticate()
            if success {
                isLocked = false
                errorMessage = nil
            } else {
                errorMessage = "No se pudo verificar tu identidad."
            }
        } catch {
            errorMessage = "No se pudo verificar tu identidad."
        }
    }
}
