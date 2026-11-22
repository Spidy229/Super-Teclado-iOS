import Combine
import os
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let engine = KeyboardEngine()
    private var host: UIHostingController<KeyboardRootView>?
    /// Fondo y teclas van en UIKit, fuera de SwiftUI: el fondo debajo de todo y las teclas encima
    /// de la vista SwiftUI (barra, paneles). Un toque en una tecla no pasa nunca por SwiftUI.
    private let backgroundView = KeyboardBackgroundView()
    private lazy var grid = KeyGridUIView(engine: engine)
    /// La barra de sugerencias, los ajustes rápidos y los avisos también van en UIKit: al escribir
    /// o abrir ⚙️ no interviene SwiftUI ni ningún `UIHostingController`.
    private lazy var suggestionBar = SuggestionBarUIView(engine: engine)
    private lazy var settingsPanel = KeyboardSettingsPanelUIView(engine: engine)
    private let toastView = KeyboardToastView()
    private var engineObserver: AnyCancellable?
    private var gridSyncScheduled = false
    private var contextRefreshScheduled = false
    /// Mide si el hilo principal se queda atascado (para el diagnóstico de toques). Es un
    /// temporizador y no un `CADisplayLink`, que podría cambiar la frecuencia de la pantalla.
    private var stallTimer: Timer?
    private var lastStallCheck: CFTimeInterval = 0
    private var appearedAt: CFTimeInterval = 0
    private static let stallInterval: CFTimeInterval = 0.1
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
        if engine.needsInputModeSwitchKey != needsInputModeSwitchKey {
            engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        }
        updateMetrics()
        engine.prepareForNewField()
        engine.refreshContext()
        // El portapapeles (leer lo copiado, imágenes incluidas, y guardarlo) se mira un momento
        // después de aparecer: así las primeras teclas no esperan a nada.
        scheduleFirstClipboardCheck()
        startClipboardMonitoring()
    }

    private func scheduleFirstClipboardCheck() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.view.window != nil else { return }
            self.engine.reloadClipsInBackground()
            // Si ya está escribiendo, lo hará el sondeo en la siguiente pausa.
            guard !self.grid.hasActiveTouches,
                  ProcessInfo.processInfo.systemUptime - self.engine.lastKeyTouch > 1.5 else { return }
            self.checkPasteboard()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        engine.prepareFeedback()
        startFrameMonitor()
        // iOS puede dar el valor definitivo de «acceso total» cuando el teclado ya está visible.
        if engine.hasFullAccess != hasFullAccess { engine.hasFullAccess = hasFullAccess }
        if engine.needsInputModeSwitchKey != needsInputModeSwitchKey {
            engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stallTimer?.invalidate()
        stallTimer = nil
        grid.suspend()
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
        // Solo lo barato: esto se ejecuta en cada recolocación de la vista.
        engine.setTraitStyle(traitCollection.userInterfaceStyle)
        updateMetrics()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncGrid()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        scheduleContextRefresh()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        scheduleContextRefresh()
    }

    /// Agrupa `textDidChange` y `selectionDidChange` cuando iOS los dispara seguidos tras la misma
    /// pulsación, evitando duplicar lecturas XPC a `textDocumentProxy`.
    private func scheduleContextRefresh() {
        guard !contextRefreshScheduled else { return }
        contextRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.contextRefreshScheduled = false
            self.engine.refreshContext()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        engine.releaseMemoryCaches()
    }

    // MARK: Portapapeles

    private var clipboardCheckInFlight = false

    /// Resultado de mirar el portapapeles fuera del hilo principal.
    private enum PasteboardOutcome: Sendable {
        case unchanged
        case seen(Int)
        case settings(Int)
        case captured(Int, Bool)
    }

    /// Captura lo copiado en otras apps. Solo lee el contenido cuando cambia `changeCount`, así
    /// iOS muestra el aviso de «pegado» una sola vez por copia. Todo se hace fuera del hilo
    /// principal: leer una imagen, o lo copiado en otro dispositivo con el portapapeles
    /// universal, puede tardar medio segundo o más y congelaba el teclado.
    func checkPasteboard() {
        guard hasFullAccess, !clipboardCheckInFlight else { return }
        // Comprobación barata en el hilo principal antes de lanzar una tarea: si el portapapeles
        // no ha cambiado, no se toca en segundo plano.
        let currentChangeCount = UIPasteboard.general.changeCount
        let lastSeen = lastSeenChangeCount
        guard currentChangeCount != lastSeen else { return }
        clipboardCheckInFlight = true
        let ownChange = engine.ownPasteboardChangeCount
        let canCapture = !engine.isIncognito
        Task { @MainActor [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                Self.readPasteboard(lastSeen: lastSeen, ownChange: ownChange, canCapture: canCapture)
            }.value
            guard let self else { return }
            self.clipboardCheckInFlight = false
            switch outcome {
            case .unchanged:
                break
            case .seen(let changeCount):
                self.lastSeenChangeCount = changeCount
            case .settings(let changeCount):
                self.lastSeenChangeCount = changeCount
                self.applySettingsFromApp(UIPasteboard.general)
            case .captured(let changeCount, let captured):
                self.lastSeenChangeCount = changeCount
                self.engine.reloadClipsInBackground(offerQuickPaste: captured)
            }
        }
    }

    nonisolated private static func readPasteboard(lastSeen: Int, ownChange: Int?, canCapture: Bool) -> PasteboardOutcome {
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastSeen else { return .unchanged }
        // Ajustes enviados desde la app cuando no hay App Group: se aplican y no se guardan.
        if pasteboard.contains(pasteboardTypes: [KeyboardSettingsTransfer.pasteboardType]) {
            return .settings(changeCount)
        }
        guard ownChange != changeCount, canCapture, SharedClipboardStore.automaticCaptureEnabled else {
            return .seen(changeCount)
        }
        // Textos, enlaces e imágenes, también cuando se copian varios a la vez. Lo que los
        // gestores de contraseñas marcan como privado no se guarda.
        return .captured(changeCount, ClipboardCapture.captureItems(from: pasteboard, changeCount: changeCount))
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
        // La caducidad también se aplica si no cambia el portapapeles o se está escribiendo.
        engine.expireClips()
        // Mientras se escribe no se pregunta a iOS por el portapapeles (es una consulta a otro
        // proceso): lo copiado se recoge en cuanto se deja de teclear o al abrir el panel.
        let idle = ProcessInfo.processInfo.systemUptime - engine.lastKeyTouch
        guard !grid.hasActiveTouches, idle > 1.5 else { return }
        checkPasteboard()
        // Esperar una pausa más clara (3 s) antes de cargar `UITextChecker` en el hilo principal.
        if idle > 3.0 {
            engine.warmUpSpellChecker()
        }
    }

    /// Reconocedores de gestos que ven los toques de las teclas (los del sistema incluidos),
    /// para el informe: si iOS añade alguno que retrasa o cancela toques, aparece aquí.
    func gestureRecognizerReport() -> [String] {
        func describe(_ recognizer: UIGestureRecognizer, on owner: String) -> String {
            var flags: [String] = []
            if recognizer.delaysTouchesBegan { flags.append("retrasa inicio") }
            if recognizer.delaysTouchesEnded { flags.append("retrasa fin") }
            if recognizer.cancelsTouchesInView { flags.append("cancela") }
            if !recognizer.isEnabled { flags.append("desactivado") }
            return "\(owner): \(type(of: recognizer))" + (flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))")
        }
        var lines: [String] = []
        var current: UIView? = grid
        while let candidate = current {
            for recognizer in candidate.gestureRecognizers ?? [] {
                lines.append(describe(recognizer, on: "\(type(of: candidate))"))
            }
            current = candidate.superview
        }
        if let window = view.window {
            for recognizer in window.gestureRecognizers ?? [] {
                lines.append(describe(recognizer, on: "ventana \(type(of: window))"))
            }
        }
        return lines
    }

    /// Memoria que le queda al teclado antes de que iOS lo cierre.
    static func recordAvailableMemory() {
        let available = os_proc_available_memory()
        guard available > 0 else { return }
        KeyboardDiagnostics.recordMemory(availableMB: Double(available) / 1_048_576)
    }

    // MARK: Diseño

    private func installKeyboardView() {
        // Alfa mínimo en la vista raíz para que nunca existan zonas transparentes sin hit-testing
        // en la ventana remota de la extensión (incluido el tema Cristal).
        view.backgroundColor = UIColor(white: 0, alpha: 0.01)
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)

        // Al escribir y en el panel de ajustes todo es UIKit puro (como en Gboard y el teclado de
        // Apple): el `UIHostingController` de SwiftUI se crea solo cuando hace falta otro panel.
        view.addSubview(suggestionBar)
        view.addSubview(grid)
        settingsPanel.isHidden = true
        view.addSubview(settingsPanel)
        toastView.onAction = { [weak self] in self?.engine.performToastAction() }
        view.addSubview(toastView)
        engineObserver = engine.objectWillChange.sink { [weak self] _ in
            self?.scheduleGridSync()
        }
        syncGrid()
    }

    private func needsSwiftUI(for panel: KeyboardPanel) -> Bool {
        switch panel {
        case .settings:
            return false
        case .typing:
            return engine.metrics.favoritesRowHeight > 0 || engine.preferences.oneHandedMode != .off
        case .clipboard, .emoji, .emojiSearch, .clipboardSearch, .editing, .themes:
            return true
        }
    }

    private func ensureSwiftUIHost() -> UIHostingController<KeyboardRootView> {
        if let host { return host }
        let controller = UIHostingController(rootView: KeyboardRootView(engine: engine))
        controller.view.backgroundColor = .clear
        controller.sizingOptions = []
        addChild(controller)
        view.insertSubview(controller.view, aboveSubview: backgroundView)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        host = controller
        return controller
    }

    private func syncSwiftUIHost(needed: Bool) {
        if needed {
            let controller = ensureSwiftUIHost()
            if controller.view.isHidden {
                controller.view.isHidden = false
                controller.view.isUserInteractionEnabled = true
            }
        } else if let hostView = host?.view, !hostView.isHidden {
            hostView.isHidden = true
            hostView.isUserInteractionEnabled = false
        }
    }

    /// Los cambios del motor se aplican a las teclas en cuanto termina el cambio (una vez aunque
    /// cambien varias cosas a la vez).
    private func scheduleGridSync() {
        guard !gridSyncScheduled else { return }
        gridSyncScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.gridSyncScheduled = false
            self.syncGrid()
        }
    }

    private func syncGrid() {
        UIView.withoutAnimation { syncGridContents() }
    }

    private func syncGridContents() {
        let preferences = engine.preferences
        let palette = KeyboardPalette.make(
            theme: preferences.theme,
            systemIsDark: engine.isDark,
            custom: preferences.customColors,
            glassTransparency: preferences.glassTransparency
        )
        backgroundView.apply(
            palette: palette,
            photo: preferences.theme == .photo ? engine.backgroundImage : nil,
            dim: preferences.backgroundDim
        )
        let panel = engine.panel
        syncSwiftUIHost(needed: needsSwiftUI(for: panel))
        syncSettingsPanel(panel: panel, palette: palette)
        syncBarAndToast(panel: panel, palette: palette)
        guard panel == .typing || panel == .emojiSearch || panel == .clipboardSearch else {
            if !grid.isHidden {
                grid.suspend()
                grid.isHidden = true
            }
            return
        }
        let layout = gridLayout(for: panel)
        if grid.frame != layout.frame { grid.frame = layout.frame }
        if grid.keyContentInsets != layout.insets { grid.keyContentInsets = layout.insets }
        grid.isHidden = false
        grid.apply(KeyGridConfiguration(engine: engine), palette: palette)
    }

    private func syncSettingsPanel(panel: KeyboardPanel, palette: KeyboardPalette) {
        guard panel == .settings else {
            if !settingsPanel.isHidden { settingsPanel.isHidden = true }
            return
        }
        let frame = view.bounds
        if settingsPanel.frame != frame { settingsPanel.frame = frame }
        let justOpened = settingsPanel.isHidden
        settingsPanel.isHidden = false
        settingsPanel.apply(palette: palette, stripHeight: engine.metrics.stripHeight, safeAreaInsets: view.safeAreaInsets)
        if justOpened { settingsPanel.refreshDiagnostics() }
    }

    private func syncBarAndToast(panel: KeyboardPanel, palette: KeyboardPalette) {
        let insets = view.safeAreaInsets
        let width = max(0, view.bounds.width - insets.left - insets.right)
        if panel == .typing {
            let frame = CGRect(x: insets.left, y: insets.top, width: width, height: engine.metrics.stripHeight)
            if suggestionBar.frame != frame { suggestionBar.frame = frame }
            suggestionBar.isHidden = false
            suggestionBar.apply(palette: palette)
        } else if !suggestionBar.isHidden {
            suggestionBar.isHidden = true
        }

        toastView.show(message: engine.toast, actionTitle: engine.toastActionTitle, palette: palette)
        if toastView.isShowing {
            let size = toastView.sizeThatFits(CGSize(width: max(0, width - 32), height: .greatestFiniteMagnitude))
            let frame = CGRect(x: insets.left + (width - size.width) / 2, y: insets.top + 4, width: size.width, height: size.height)
            if toastView.bounds.size != frame.size || toastView.center != CGPoint(x: frame.midX, y: frame.midY) {
                // Con la transformación de la animación de entrada, `frame` no se puede asignar.
                toastView.bounds = CGRect(origin: .zero, size: frame.size)
                toastView.center = CGPoint(x: frame.midX, y: frame.midY)
            }
            view.bringSubviewToFront(toastView)
        }
    }

    /// Cubre todo el ancho y alto disponible debajo de la barra para que no quede ningún hueco
    /// muerto en los bordes o al fondo; las teclas visuales respetan los márgenes seguros.
    private func gridLayout(for panel: KeyboardPanel) -> (frame: CGRect, insets: UIEdgeInsets) {
        let metrics = engine.metrics
        let showsFavorites = metrics.favoritesRowHeight > 0 && panel == .typing
        var top = metrics.stripHeight + (showsFavorites ? metrics.favoritesRowHeight : 0)
        var minHeight = metrics.keyAreaHeight + (showsFavorites ? 0 : metrics.favoritesRowHeight)
        if panel == .clipboardSearch {
            top += 50
            minHeight -= 50
        }
        let insets = view.safeAreaInsets
        let safeWidth = max(0, view.bounds.width - insets.left - insets.right)
        let mode = engine.preferences.oneHandedMode
        let side: CGFloat = mode == .off ? 0 : min(72, safeWidth * 0.17)
        let originY = insets.top + top
        let availableHeight = view.bounds.height > originY
            ? (view.bounds.height - originY)
            : max(0, minHeight)
        let bottomVisualInset = max(0, min(insets.bottom, availableHeight - 1))

        switch mode {
        case .off:
            return (
                CGRect(x: 0, y: originY, width: view.bounds.width, height: availableHeight),
                UIEdgeInsets(top: 0, left: insets.left, bottom: bottomVisualInset, right: insets.right)
            )
        case .right:
            let originX = insets.left + side
            return (
                CGRect(x: originX, y: originY, width: max(0, view.bounds.width - originX), height: availableHeight),
                UIEdgeInsets(top: 0, left: 0, bottom: bottomVisualInset, right: insets.right)
            )
        case .left:
            let width = max(0, view.bounds.width - insets.right - side)
            return (
                CGRect(x: 0, y: originY, width: width, height: availableHeight),
                UIEdgeInsets(top: 0, left: insets.left, bottom: bottomVisualInset, right: 0)
            )
        }
    }

    // MARK: Diagnóstico

    private func startFrameMonitor() {
        stallTimer?.invalidate()
        lastStallCheck = CACurrentMediaTime()
        appearedAt = lastStallCheck
        let timer = Timer(timeInterval: Self.stallInterval, target: self, selector: #selector(stallTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    /// Si el temporizador llega tarde, el hilo principal estuvo ocupado y los toques esperaron.
    @objc private func stallTick() {
        let now = CACurrentMediaTime()
        let lateness = now - lastStallCheck - Self.stallInterval
        engine.touchDiagnostics.recordMainThreadDelay(lateness)
        if lateness > 0.1 {
            // Junto a los últimos toques, para ver si se congela al abrir o mientras escribe.
            engine.touchDiagnostics.log(String(format: "BLOQUEO %.0f ms (%.1f s tras abrir)", lateness * 1000, now - appearedAt))
        }
        lastStallCheck = now
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
