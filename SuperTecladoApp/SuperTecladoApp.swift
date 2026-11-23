import SwiftData
import SwiftUI

@main
struct SuperTecladoApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ClipboardItem.self)
        } catch {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: ClipboardItem.self, configurations: configuration)
            } catch {
                fatalError("No se pudo crear el almacenamiento de recuperación: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("requireBiometrics") private var requireBiometrics = false
    @StateObject private var lockController = AppLockController()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if requireBiometrics && lockController.isLocked {
                LockView(controller: lockController)
            } else {
                ContentView()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .task {
            // La bienvenida solo aparece si nunca se ha usado el teclado con acceso total.
            let keyboardUsed = (SharedClipboardStore.sharedDefaults?.double(forKey: KeyboardPreferenceKey.lastActive) ?? 0) > 0
            if !hasCompletedOnboarding && !keyboardUsed { showOnboarding = true }
            if requireBiometrics {
                await lockController.unlock()
            } else {
                lockController.isLocked = false
            }
        }
        .onChange(of: requireBiometrics) { _, enabled in
            lockController.isLocked = enabled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && requireBiometrics {
                lockController.lock()
            }
        }
    }
}
