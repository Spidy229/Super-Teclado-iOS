import os
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let engine = KeyboardEngine()
    private var host: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var clipboardTimer: Timer?
    private static let lastChangeCountKey = "super-teclado-last-pasteboard-change"
    /// Si este proceso ya marcó la sesión como abierta (para detectar cierres inesperados).
    private static var sessionMarkedOpen = false

    private var lastSeenChangeCount: Int {
        get { UserDefaults.standard.object(forKey: Self.lastChangeCountKey) as? Int ?? -1 }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastChangeCountKey) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Se marca la sesión lo antes posible: si iOS cierra el teclado al arrancar, la próxima
        // vez se sabe y, tras dos cierres seguidos, arranca en modo seguro.
        if hasFullAccess { markSessionOpen() }
        engine.safeMode = KeyboardDiagnostics.load().isSafeModeActive
        engine.controller = self
        engine.hasFullAccess = hasFullAccess
        engine.loadPreferences()
        engine.reloadClips()
        installKeyboardView()

        let constraint = view.heightAnchor.constraint(equalToConstant: engine.metrics.totalHeight)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint

        if !engine.safeMode { requestLexicon() }
    }

    private func markSessionOpen() {
        guard !Self.sessionMarkedOpen else { return }
        Self.sessionMarkedOpen = true
        KeyboardDiagnostics.recordSessionStart()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.hasFullAccess = hasFullAccess
        if hasFullAccess {
            // La app lo usa para mostrar que el teclado está activado y con acceso total.
            SharedClipboardStore.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: KeyboardPreferenceKey.lastActive)
            markSessionOpen()
            Self.recordAvailableMemory()
        }
        if engine.safeMode {
            engine.showToast("Modo seguro: sin sugerencias tras varios cierres. Se quita solo al usarlo con normalidad.")
        }
        engine.loadPreferences()
        engine.setTraitStyle(traitCollection.userInterfaceStyle)
        updateMetrics()
        engine.reloadClips()
        checkPasteboard()
        engine.prepareForNewField()
        engine.refreshContext()
        startClipboardMonitoring()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS puede dar el valor definitivo de «acceso total» cuando el teclado ya está visible.
        if engine.hasFullAccess != hasFullAccess { engine.hasFullAccess = hasFullAccess }
        removeSystemTouchDelays()
    }

    /// Los gestos del sistema (bordes de la pantalla, barra de inicio) retrasan los toques del
    /// teclado hasta descartar que sean suyos. Eso hacía que las teclas de los bordes y el botón
    /// de volver respondieran tarde o no respondieran.
    private func removeSystemTouchDelays() {
        var current: UIView? = view
        while let candidate = current {
            candidate.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
            current = candidate.superview
        }
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        if engine.panel != .typing { engine.closePanel() }
        if hasFullAccess {
            Self.recordAvailableMemory()
            KeyboardDiagnostics.recordSessionEnd()
            Self.sessionMarkedOpen = false
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if engine.needsInputModeSwitchKey != needsInputModeSwitchKey {
            engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        }
        engine.setTraitStyle(traitCollection.userInterfaceStyle)
        updateMetrics()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        engine.refreshContext()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        engine.refreshContext()
    }

    // MARK: Portapapeles

    /// Captura lo copiado en otras apps. Solo lee el contenido cuando cambia `changeCount`, así
    /// iOS muestra el aviso de «pegado» una sola vez por copia.
    func checkPasteboard() {
        guard hasFullAccess else { return }
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastSeenChangeCount else { return }
        lastSeenChangeCount = changeCount
        // Ajustes enviados desde la app cuando no hay App Group: se aplican y no se guardan.
        if pasteboard.contains(pasteboardTypes: [KeyboardSettingsTransfer.pasteboardType]) {
            applySettingsFromApp(pasteboard)
            return
        }
        guard engine.ownPasteboardChangeCount != changeCount,
              !engine.isIncognito,
              SharedClipboardStore.automaticCaptureEnabled else { return }

        // Textos, enlaces e imágenes, también cuando se copian varios a la vez. Lo que los
        // gestores de contraseñas marcan como privado no se guarda.
        let captured = ClipboardCapture.captureItems(from: pasteboard, changeCount: changeCount)

        engine.reloadClips()
        if captured { engine.offerQuickPaste() }
    }

    private func applySettingsFromApp(_ pasteboard: UIPasteboard) {
        guard let data = pasteboard.data(forPasteboardType: KeyboardSettingsTransfer.pasteboardType),
              KeyboardSettingsTransfer.apply(data, to: SharedClipboardStore.sharedDefaults) > 0 else { return }
        // Se borra para que no se quede en el portapapeles ni se vuelva a aplicar.
        pasteboard.items = []
        lastSeenChangeCount = pasteboard.changeCount
        engine.ownPasteboardChangeCount = pasteboard.changeCount
        engine.loadPreferences()
        updateMetrics()
        engine.refreshContext()
        engine.showToast("Ajustes de la app aplicados")
    }

    private func startClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(pollClipboard),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func pollClipboard() {
        // Mientras se escribe no se pregunta a iOS por el portapapeles (es una consulta a otro
        // proceso): lo copiado se recoge en cuanto se deja de teclear o al abrir el panel.
        guard ProcessInfo.processInfo.systemUptime - engine.lastKeyTouch > 1.5 else { return }
        checkPasteboard()
    }

    /// Memoria que le queda al teclado antes de que iOS lo cierre.
    static func recordAvailableMemory() {
        let available = os_proc_available_memory()
        guard available > 0 else { return }
        KeyboardDiagnostics.recordMemory(availableMB: Double(available) / 1_048_576)
    }

    // MARK: Diseño

    private func installKeyboardView() {
        let controller = UIHostingController(rootView: KeyboardRootView(engine: engine))
        controller.view.backgroundColor = .clear
        controller.sizingOptions = []
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        host = controller
    }

    private func updateMetrics() {
        let isPad = traitCollection.userInterfaceIdiom == .pad
        let isLandscape = isPad
            ? view.bounds.width > 900
            : traitCollection.verticalSizeClass == .compact
        let metrics = KeyboardMetrics.make(
            isPad: isPad,
            isLandscape: isLandscape,
            numberRow: engine.preferences.numberRow,
            scale: engine.preferences.height.scale,
            favoritesRow: engine.preferences.favoritesRow
        )
        if metrics != engine.metrics { engine.metrics = metrics }
        if heightConstraint?.constant != metrics.totalHeight {
            heightConstraint?.constant = metrics.totalHeight
        }
    }

    // MARK: Diccionario del usuario

    /// Sustituciones de texto y nombres de contactos que iOS comparte con los teclados.
    private func requestLexicon() {
        // iOS no garantiza en qué hilo llega el resultado. El cierre es @Sendable para que
        // Swift no compruebe el hilo al entrar (eso cerraría el teclado) y el diccionario se
        // lee después en el hilo principal, que es donde UILexicon puede usarse.
        requestSupplementaryLexicon { @Sendable [weak self] lexicon in
            nonisolated(unsafe) let lexicon = lexicon
            Task { @MainActor in
                let entries = lexicon.entries.map { (input: $0.userInput, replacement: $0.documentText) }
                self?.engine.setLexicon(entries)
            }
        }
    }
}
