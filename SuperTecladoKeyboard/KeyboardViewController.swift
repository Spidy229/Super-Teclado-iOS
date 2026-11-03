import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let engine = KeyboardEngine()
    private var host: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var clipboardTimer: Timer?
    private static let lastChangeCountKey = "super-teclado-last-pasteboard-change"

    private var lastSeenChangeCount: Int {
        get { UserDefaults.standard.object(forKey: Self.lastChangeCountKey) as? Int ?? -1 }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastChangeCountKey) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        engine.controller = self
        engine.hasFullAccess = hasFullAccess
        engine.loadPreferences()
        engine.reloadClips()
        installKeyboardView()

        let constraint = view.heightAnchor.constraint(equalToConstant: engine.metrics.totalHeight)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint

        requestLexicon()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.hasFullAccess = hasFullAccess
        if hasFullAccess {
            // La app lo usa para mostrar que el teclado está activado y con acceso total.
            SharedClipboardStore.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: KeyboardPreferenceKey.lastActive)
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        if engine.panel != .typing { engine.closePanel() }
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
        guard engine.ownPasteboardChangeCount != changeCount,
              !engine.isIncognito,
              SharedClipboardStore.automaticCaptureEnabled else { return }

        // Textos, enlaces e imágenes, también cuando se copian varios a la vez. Lo que los
        // gestores de contraseñas marcan como privado no se guarda.
        let captured = ClipboardCapture.captureItems(from: pasteboard, changeCount: changeCount)

        engine.reloadClips()
        if captured { engine.offerQuickPaste() }
    }

    private func startClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(
            timeInterval: 0.8,
            target: self,
            selector: #selector(pollClipboard),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func pollClipboard() {
        checkPasteboard()
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
            scale: engine.preferences.height.scale
        )
        if metrics != engine.metrics { engine.metrics = metrics }
        if heightConstraint?.constant != metrics.totalHeight {
            heightConstraint?.constant = metrics.totalHeight
        }
    }

    // MARK: Diccionario del usuario

    /// Sustituciones de texto y nombres de contactos que iOS comparte con los teclados.
    private func requestLexicon() {
        requestSupplementaryLexicon { [weak self] lexicon in
            // UILexicon está aislado al hilo principal; UIKit entrega el resultado allí.
            let entries = lexicon.entries.map { (input: $0.userInput, replacement: $0.documentText) }
            self?.engine.setLexicon(entries)
        }
    }
}
