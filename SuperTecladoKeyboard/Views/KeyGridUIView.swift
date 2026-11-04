import SwiftUI
import UIKit

/// Lo que la cuadrícula necesita para dibujarse. Si no cambia, no se toca ninguna tecla.
struct KeyGridConfiguration: Equatable {
    var rows: [[KeySpec]] = []
    var showsNumberRow = false
    var page: KeyboardPage = .letters
    var shift: ShiftState = .off
    var returnKeyType: UIReturnKeyType = .default
    var spaceTitle = ""
    var keyBorders = true
    var keyPopups = true
    var labelScale: CGFloat = 1
    var longPressDelay = 330
    var showsGlideTrail = true
}

/// Las teclas se dibujan y se tocan con UIKit, como en Gboard y el teclado de Apple: una sola
/// vista recibe todos los dedos, resalta la tecla en cuanto se toca y escribe al levantar el
/// dedo sin pasar por SwiftUI.
struct KeyGridRepresentable: UIViewRepresentable {
    let engine: KeyboardEngine
    let configuration: KeyGridConfiguration
    let palette: KeyboardPalette

    func makeUIView(context: Context) -> KeyGridUIView {
        let view = KeyGridUIView(engine: engine)
        view.apply(configuration, palette: palette)
        return view
    }

    func updateUIView(_ view: KeyGridUIView, context: Context) {
        view.apply(configuration, palette: palette)
    }

    static func dismantleUIView(_ view: KeyGridUIView, coordinator: ()) {
        view.tearDown()
    }
}

/// Colores del tema ya convertidos para UIKit.
struct KeyGridColors {
    let key: UIColor
    let specialKey: UIColor
    let keyPressed: UIColor
    let text: UIColor
    let secondaryText: UIColor
    let accent: UIColor
    let accentText: UIColor
    let shadow: UIColor
    let popup: UIColor

    init(_ palette: KeyboardPalette) {
        key = UIColor(palette.key)
        specialKey = UIColor(palette.specialKey)
        keyPressed = UIColor(palette.keyPressed)
        text = UIColor(palette.text)
        secondaryText = UIColor(palette.secondaryText)
        accent = UIColor(palette.accent)
        accentText = UIColor(palette.accentText)
        shadow = UIColor(palette.shadow)
        popup = UIColor(palette.popup)
    }
}

/// Estado de un dedo sobre el teclado.
@MainActor
private final class TouchState {
    enum Phase {
        /// Tecla pulsada, pendiente de escribir al levantar el dedo.
        case pressed
        /// Mostrando los caracteres alternativos de la pulsación larga.
        case alternates
        /// Escribiendo deslizando.
        case gliding
        /// Moviendo el cursor con la barra espaciadora.
        case cursor
        /// Ya se escribió porque otro dedo tocó antes de levantar este (como al teclear rápido).
        case committed
        /// Tecla del globo: la gestiona iOS.
        case system
        case ignored
    }

    var keyID: String
    var spec: KeySpec
    var frame: CGRect
    let start: CGPoint
    var last: CGPoint
    var phase: Phase = .pressed
    var selectedAlternate = 0
    var alternatesStart: CGFloat = 0
    var optionWidth: CGFloat = 1
    var cursorStep = 0
    var swipeSteps = 0
    var popup: KeyPopupUIView?
    var timer: Task<Void, Never>?

    init(keyID: String, spec: KeySpec, frame: CGRect, start: CGPoint) {
        self.keyID = keyID
        self.spec = spec
        self.frame = frame
        self.start = start
        last = start
    }
}

final class KeyGridUIView: UIView {
    private struct GridKey {
        let id: String
        let spec: KeySpec
        let frame: CGRect
        let view: KeyCapUIView
    }

    private struct RowBand {
        let maxY: CGFloat
        let range: Range<Int>
    }

    private let engine: KeyboardEngine
    private var configuration = KeyGridConfiguration()
    private var palette: KeyboardPalette?
    private var colors = KeyGridColors(KeyboardPalette.make(theme: .dark, systemIsDark: true))
    private var keys: [GridKey] = []
    private var keyIndexByID: [String: Int] = [:]
    private var rowBands: [RowBand] = []
    private var keyViews: [String: KeyCapUIView] = [:]
    private var laidOutSize: CGSize = .zero
    private var glideTarget = GlideTarget(centers: [:], keyWidth: 1)
    private var states: [ObjectIdentifier: TouchState] = [:]
    /// Orden en que tocaron los dedos, para escribir en ese orden al teclear rápido.
    private var touchOrder: [ObjectIdentifier] = []
    private var popupPool: [KeyPopupUIView] = []
    private var allPopups: [KeyPopupUIView] = []
    private let trailLayer = CAShapeLayer()
    private var trailPoints: [CGPoint] = []

    init(engine: KeyboardEngine) {
        self.engine = engine
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        trailLayer.fillColor = nil
        trailLayer.lineWidth = 6
        trailLayer.lineCap = .round
        trailLayer.lineJoin = .round
        trailLayer.zPosition = 100
        trailLayer.actions = [
            "path": NSNull(), "opacity": NSNull(), "strokeColor": NSNull(),
            "bounds": NSNull(), "position": NSNull()
        ]
        layer.addSublayer(trailLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    // MARK: Configuración

    func apply(_ newConfiguration: KeyGridConfiguration, palette newPalette: KeyboardPalette) {
        let paletteChanged = palette != newPalette
        guard paletteChanged || newConfiguration != configuration || keys.isEmpty else { return }
        let layoutChanged = keys.isEmpty
            || newConfiguration.rows != configuration.rows
            || newConfiguration.showsNumberRow != configuration.showsNumberRow
        configuration = newConfiguration
        if paletteChanged {
            palette = newPalette
            colors = KeyGridColors(newPalette)
            trailLayer.strokeColor = colors.accent.withAlphaComponent(0.75).cgColor
        }
        if layoutChanged {
            rebuildKeys()
        } else {
            keys.forEach(configure)
        }
    }

    /// La vista sale de pantalla (otro panel): se sueltan los dedos sin escribir nada.
    func tearDown() {
        cancelAllTouches()
        allPopups.forEach { $0.removeFromSuperview() }
        allPopups = []
        popupPool = []
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelAllTouches() }
    }

    private func rebuildKeys() {
        var unused = keyViews
        var updated: [String: KeyCapUIView] = [:]
        for (index, spec) in configuration.rows.joined().enumerated() {
            let id = updated[spec.id] == nil ? spec.id : "\(spec.id)#\(index)"
            if let view = unused.removeValue(forKey: id) {
                updated[id] = view
            } else {
                let view = KeyCapUIView()
                addSubview(view)
                updated[id] = view
            }
        }
        unused.values.forEach { $0.removeFromSuperview() }
        keyViews = updated
        laidOutSize = .zero
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if trailLayer.frame != bounds { trailLayer.frame = bounds }
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        layoutKeys()
    }

    /// Reparte el ancho en unidades igual que antes, para que el trazo deslizado y los centros
    /// de las teclas coincidan.
    private func layoutKeys() {
        let rows = configuration.rows
        let width = bounds.width
        let geometry = KeyGridGeometry(size: bounds.size, showsNumberRow: configuration.showsNumberRow, rowCount: rows.count)
        let padding = KeyGridGeometry.horizontalPadding
        // El iPad tiene filas más largas (intro, comas, segunda tecla de mayúsculas…).
        let totalUnits = max(10, rows.map { $0.reduce(0) { $0 + $1.units } }.max() ?? 10)
        let unit = (width - padding * 2) / totalUnits

        var newKeys: [GridKey] = []
        var bands: [RowBand] = []
        var centers: [Character: CGPoint] = [:]
        var seen: Set<String> = []
        var flatIndex = 0
        for (rowIndex, row) in rows.enumerated() {
            let height = geometry.height(ofRow: rowIndex)
            let originY = geometry.originY(ofRow: rowIndex)
            let rowWidth = row.reduce(0) { $0 + $1.units } * unit
            var x = padding + max(0, (width - padding * 2 - rowWidth) / 2)
            let first = newKeys.count
            for spec in row {
                let id = seen.contains(spec.id) ? "\(spec.id)#\(flatIndex)" : spec.id
                seen.insert(id)
                flatIndex += 1
                let frame = CGRect(x: x, y: originY, width: spec.units * unit, height: height)
                x += spec.units * unit
                guard let view = keyViews[id] else { continue }
                view.frame = frame
                newKeys.append(GridKey(id: id, spec: spec, frame: frame, view: view))
                if configuration.page == .letters, case .character(let value) = spec.kind,
                   value.count == 1, let letter = value.first, letter.isLetter || letter == "'" {
                    centers[letter] = CGPoint(x: frame.midX, y: frame.midY)
                }
            }
            let isLast = rowIndex == rows.count - 1
            bands.append(RowBand(maxY: isLast ? .infinity : originY + height, range: first..<newKeys.count))
        }
        keys = newKeys
        rowBands = bands
        keyIndexByID = Dictionary(uniqueKeysWithValues: newKeys.enumerated().map { ($1.id, $0) })
        glideTarget = GlideTarget(centers: centers, keyWidth: unit)
        accessibilityElements = newKeys.map(\.view)
        keys.forEach(configure)
    }

    // MARK: Aspecto de cada tecla

    private func displayText(_ value: String, caseSensitive: Bool) -> String {
        guard caseSensitive, configuration.page == .letters, configuration.shift != .off else { return value }
        return value.uppercased()
    }

    private func characterFontSize(_ value: String, height: CGFloat) -> CGFloat {
        min(25, height * 0.46) * (value.count > 2 ? 0.7 : 1) * configuration.labelScale
    }

    private func isHighlighted(_ id: String) -> Bool {
        states.values.contains { state in
            state.keyID == id && (state.phase == .pressed || state.phase == .alternates || state.phase == .system)
        }
    }

    private var isMovingCursor: Bool {
        states.values.contains { $0.phase == .cursor }
    }

    private func refreshKey(_ id: String) {
        guard let index = keyIndexByID[id] else { return }
        configure(keys[index])
    }

    private func configure(_ key: GridKey) {
        let view = key.view
        let height = key.frame.height
        let highlighted = isHighlighted(key.id)
        var fill = colors.specialKey
        var alwaysFilled = false
        var showsPressed = highlighted

        switch key.spec.kind {
        case .character(let value):
            fill = colors.key
            showsPressed = highlighted && !configuration.keyPopups
            let text = displayText(value, caseSensitive: key.spec.isLetter)
            view.setText(text, font: .systemFont(ofSize: characterFontSize(value, height: height)), color: colors.text)
            view.setHint(
                key.spec.hint,
                font: .systemFont(ofSize: max(9, height * 0.19), weight: .medium),
                color: colors.secondaryText
            )
            view.accessibilityLabel = text
        case .space:
            fill = colors.key
            view.hideHint()
            if isMovingCursor {
                showsPressed = false
                view.setCursorSymbols(color: colors.accent)
            } else {
                view.setText(configuration.spaceTitle, font: .systemFont(ofSize: min(15, height * 0.3)), color: colors.secondaryText)
            }
            view.accessibilityLabel = "Espacio"
        case .shift:
            if configuration.shift != .off { fill = colors.key }
            view.setIcon(
                shiftSymbol,
                pointSize: min(20, height * 0.38),
                weight: .medium,
                color: configuration.shift == .locked ? colors.accent : colors.text
            )
            view.accessibilityLabel = "Mayúsculas"
        case .delete:
            view.setIcon(highlighted ? "delete.left.fill" : "delete.left", pointSize: min(21, height * 0.4), weight: .regular, color: colors.text)
            view.accessibilityLabel = "Borrar"
        case .returnKey:
            fill = colors.accent
            alwaysFilled = true
            view.setIcon(returnSymbol, pointSize: min(20, height * 0.38), weight: .semibold, color: colors.accentText)
            view.accessibilityLabel = "Intro"
        case .globe:
            view.setIcon("globe", pointSize: min(19, height * 0.36), weight: .regular, color: colors.text)
            view.accessibilityLabel = "Siguiente teclado"
        case .emoji:
            view.setIcon("face.smiling", pointSize: min(20, height * 0.38), weight: .regular, color: colors.text)
            view.accessibilityLabel = "Emojis"
        case .page(_, let title):
            view.hideHint()
            view.setText(title, font: .systemFont(ofSize: min(15, height * 0.3), weight: .medium), color: colors.text)
            view.accessibilityLabel = title
        case .dismiss:
            view.setIcon("keyboard.chevron.compact.down", pointSize: min(19, height * 0.36), weight: .regular, color: colors.text)
            view.accessibilityLabel = "Ocultar teclado"
        }

        let showsBorder = configuration.keyBorders || alwaysFilled
        view.setCap(
            fill: showsPressed ? colors.keyPressed : (showsBorder ? fill : .clear),
            shadow: showsBorder ? colors.shadow : nil
        )
    }

    private var shiftSymbol: String {
        switch configuration.shift {
        case .off: "shift"
        case .on: "shift.fill"
        case .locked: "capslock.fill"
        }
    }

    private var returnSymbol: String {
        switch configuration.returnKeyType {
        case .go, .join, .continue: "arrow.right"
        case .google, .search, .yahoo: "magnifyingglass"
        case .send: "paperplane.fill"
        case .next: "arrow.right.to.line"
        case .done: "checkmark"
        case .route: "arrow.triangle.turn.up.right.diamond"
        case .emergencyCall: "phone.fill"
        default: "return"
        }
    }

    // MARK: Toques

    /// Tecla más cercana al dedo: los huecos entre teclas y los bordes cuentan para la de al lado.
    private func keyIndex(at point: CGPoint) -> Int? {
        guard let band = rowBands.first(where: { point.y < $0.maxY }) ?? rowBands.last else { return nil }
        var best: Int?
        var bestDistance = CGFloat.infinity
        for index in band.range {
            let frame = keys[index].frame
            let distance = point.x < frame.minX ? frame.minX - point.x : max(0, point.x - frame.maxX)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
            if distance == 0 { break }
        }
        return best
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            begin(touch, event: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let state = states[ObjectIdentifier(touch)] else { continue }
            if state.phase == .gliding {
                // Todos los puntos intermedios (hasta 120 por segundo) para un trazo más fiel.
                let samples = event?.coalescedTouches(for: touch) ?? [touch]
                for sample in samples {
                    let point = sample.location(in: self)
                    engine.extendGlide(to: point)
                    addTrailPoint(point)
                }
                state.last = touch.location(in: self)
                continue
            }
            let point = touch.location(in: self)
            state.last = point
            move(state, to: point, event: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            end(touch, event: event, cancelled: false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            end(touch, event: event, cancelled: true)
        }
    }

    private func begin(_ touch: UITouch, event: UIEvent?) {
        let id = ObjectIdentifier(touch)
        let point = touch.location(in: self)
        guard let index = keyIndex(at: point) else { return }
        let key = keys[index]
        let state = TouchState(keyID: key.id, spec: key.spec, frame: key.frame, start: point)
        states[id] = state
        touchOrder.append(id)

        // Mientras se escribe deslizando no cuentan otros dedos.
        if states.values.contains(where: { $0.phase == .gliding }) {
            state.phase = .ignored
            return
        }
        // Como en Gboard y el teclado de Apple: si toca otro dedo antes de levantar el anterior,
        // la tecla anterior se escribe ya, para no perder ni desordenar letras al teclear rápido.
        commitPendingTouches(except: id)

        switch key.spec.kind {
        case .character:
            engine.keyFeedback(.character)
            showPreview(for: state)
            scheduleLongPress(for: state)
        case .space:
            engine.keyFeedback(.character)
        case .delete:
            engine.keyFeedback(.delete)
            engine.deleteBackward()
            startDeleteRepeat(for: state)
        case .shift:
            engine.keyFeedback(.modifier)
            engine.tapShift()
        case .page(let target, _):
            engine.keyFeedback(.modifier)
            engine.setPage(target)
        case .globe:
            state.phase = .system
            engine.keyFeedback(.modifier)
            if let event { engine.controller?.handleInputModeList(from: self, with: event) }
        case .returnKey, .emoji, .dismiss:
            engine.keyFeedback(.modifier)
        }
        configure(key)
    }

    private func commitPendingTouches(except newID: ObjectIdentifier) {
        for id in touchOrder where id != newID {
            guard let state = states[id], state.phase == .pressed else { continue }
            switch state.spec.kind {
            case .character, .space:
                state.timer?.cancel()
                state.timer = nil
                state.phase = .committed
                hidePopup(of: state)
                commit(state)
                refreshKey(state.keyID)
            default:
                break
            }
        }
    }

    private func move(_ state: TouchState, to point: CGPoint, event: UIEvent?) {
        switch state.phase {
        case .alternates:
            let index = alternateIndex(for: state, x: point.x)
            if index != state.selectedAlternate {
                state.selectedAlternate = index
                state.popup?.select(index, colors: colors)
            }
        case .cursor:
            let step = Int((point.x - state.start.x) / 9)
            if step != state.cursorStep {
                engine.moveCursor(by: step - state.cursorStep)
                engine.keyFeedback(.character)
                state.cursorStep = step
            }
        case .system:
            if let event { engine.controller?.handleInputModeList(from: self, with: event) }
        case .pressed:
            switch state.spec.kind {
            case .character: characterMoved(state, to: point)
            case .space: spaceMoved(state, to: point)
            case .delete: deleteMoved(state, to: point)
            default: break
            }
        case .gliding, .committed, .ignored:
            break
        }
    }

    private func characterMoved(_ state: TouchState, to point: CGPoint) {
        let distance = GlideDecoder.distance(state.start, point)
        let activeTouches = states.values.filter { $0.phase != .committed && $0.phase != .ignored }.count
        if state.spec.isLetter, engine.canGlide, activeTouches == 1,
           distance > max(18, glideTarget.keyWidth * 0.6) {
            // El dedo ha salido de la tecla: empieza la escritura deslizando.
            state.timer?.cancel()
            state.timer = nil
            state.phase = .gliding
            hidePopup(of: state)
            refreshKey(state.keyID)
            engine.beginGlide(at: state.start, target: glideTarget)
            beginTrail(at: state.start)
            engine.extendGlide(to: point)
            addTrailPoint(point)
            return
        }
        guard !(state.spec.isLetter && engine.canGlide) else { return }
        // Sin escritura deslizando, la tecla que cuenta es la que queda bajo el dedo.
        guard let index = keyIndex(at: point), keys[index].id != state.keyID,
              case .character = keys[index].spec.kind else { return }
        let previous = state.keyID
        state.keyID = keys[index].id
        state.spec = keys[index].spec
        state.frame = keys[index].frame
        refreshKey(previous)
        refreshKey(state.keyID)
        showPreview(for: state)
        scheduleLongPress(for: state)
    }

    private func spaceMoved(_ state: TouchState, to point: CGPoint) {
        let width = point.x - state.start.x
        guard abs(width) > 16 else { return }
        state.phase = .cursor
        state.cursorStep = Int(width / 9)
        refreshKey(state.keyID)
    }

    private func deleteMoved(_ state: TouchState, to point: CGPoint) {
        // Deslizar hacia la izquierda borra palabras completas.
        let steps = Int(-(point.x - state.start.x) / 24)
        guard steps > state.swipeSteps else { return }
        state.timer?.cancel()
        state.timer = nil
        while state.swipeSteps < steps {
            state.swipeSteps += 1
            engine.deleteWordBackward()
            engine.keyFeedback(.delete)
        }
    }

    private func end(_ touch: UITouch, event: UIEvent?, cancelled: Bool) {
        let id = ObjectIdentifier(touch)
        guard let state = states.removeValue(forKey: id) else { return }
        touchOrder.removeAll { $0 == id }
        state.timer?.cancel()
        state.timer = nil
        hidePopup(of: state)

        if cancelled {
            if state.phase == .gliding {
                engine.cancelGlide()
                fadeTrail()
            }
        } else {
            finish(state, event: event)
        }
        refreshKey(state.keyID)
    }

    private func finish(_ state: TouchState, event: UIEvent?) {
        switch state.phase {
        case .pressed:
            commit(state)
        case .alternates:
            if state.spec.alternates.indices.contains(state.selectedAlternate) {
                engine.insertCharacter(state.spec.alternates[state.selectedAlternate], caseSensitive: state.spec.isLetter)
            }
        case .gliding:
            fadeTrail()
            // Un desliz corto al teclear rápido cuenta como pulsación normal.
            if !engine.endGlide(), case .character(let value) = state.spec.kind {
                engine.insertCharacter(value, caseSensitive: state.spec.isLetter)
            }
        case .system:
            if let event { engine.controller?.handleInputModeList(from: self, with: event) }
        case .cursor, .committed, .ignored:
            break
        }
    }

    private func commit(_ state: TouchState) {
        switch state.spec.kind {
        case .character(let value): engine.insertCharacter(value, caseSensitive: state.spec.isLetter)
        case .space: engine.insertSpace()
        case .returnKey: engine.insertReturn()
        case .emoji: engine.open(.emoji)
        case .dismiss: engine.dismissKeyboard()
        // Borrar, mayúsculas y ?123 ya actuaron al tocar; el globo lo gestiona iOS.
        case .delete, .shift, .page, .globe: break
        }
    }

    private func cancelAllTouches() {
        for state in states.values {
            state.timer?.cancel()
            state.timer = nil
            hidePopup(of: state)
            if state.phase == .gliding { engine.cancelGlide() }
        }
        states.removeAll()
        touchOrder.removeAll()
        trailPoints = []
        trailLayer.path = nil
        keys.forEach(configure)
    }

    // MARK: Pulsación larga y repetición

    private func scheduleLongPress(for state: TouchState) {
        state.timer?.cancel()
        state.timer = nil
        guard !state.spec.alternates.isEmpty else { return }
        let delay = configuration.longPressDelay
        state.timer = Task { @MainActor [weak self, weak state] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, let state, state.phase == .pressed else { return }
            self.showAlternates(for: state)
        }
    }

    private func startDeleteRepeat(for state: TouchState) {
        state.timer?.cancel()
        state.timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            var count = 0
            while !Task.isCancelled, let engine = self?.engine {
                if count < 20 {
                    engine.deleteBackward()
                    try? await Task.sleep(for: .milliseconds(65))
                } else {
                    engine.deleteWordBackward()
                    try? await Task.sleep(for: .milliseconds(200))
                }
                count += 1
            }
        }
    }

    // MARK: Ventanas emergentes

    /// Las ventanas emergentes van en la vista raíz del teclado para poder salir por encima de
    /// la fila superior sin que nada las recorte.
    private var overlayHost: UIView {
        engine.controller?.view ?? self
    }

    private func dequeuePopup() -> KeyPopupUIView {
        let popup: KeyPopupUIView
        if let reused = popupPool.popLast() {
            popup = reused
        } else {
            popup = KeyPopupUIView()
            allPopups.append(popup)
        }
        let host = overlayHost
        if popup.superview !== host {
            popup.removeFromSuperview()
            host.addSubview(popup)
        } else {
            host.bringSubviewToFront(popup)
        }
        popup.isHidden = false
        return popup
    }

    private func hidePopup(of state: TouchState) {
        guard let popup = state.popup else { return }
        popup.isHidden = true
        state.popup = nil
        popupPool.append(popup)
    }

    private func showPreview(for state: TouchState) {
        guard configuration.keyPopups, case .character(let value) = state.spec.kind else {
            hidePopup(of: state)
            return
        }
        let frame = state.frame
        let popupHeight = max(36, frame.height - 8)
        let rect = CGRect(x: frame.minX, y: frame.minY + 2 - popupHeight, width: frame.width, height: popupHeight)
        let popup = state.popup ?? dequeuePopup()
        state.popup = popup
        // La ventana usa el estado actual de mayúsculas aunque las etiquetas aún no se hayan
        // actualizado (al teclear muy rápido tras una mayúscula).
        popup.showPreview(
            engine.displayText(for: value, caseSensitive: state.spec.isLetter),
            font: .systemFont(ofSize: min(34, characterFontSize(value, height: frame.height) * 1.35)),
            colors: colors,
            frame: convert(rect, to: overlayHost)
        )
    }

    private func showAlternates(for state: TouchState) {
        let options = state.spec.alternates
        guard !options.isEmpty else { return }
        let frame = state.frame
        let popupHeight = max(36, frame.height - 8)
        let optionWidth = max(30, min(44, frame.width - 6))
        let barWidth = CGFloat(options.count) * optionWidth + 6
        var start = frame.minX + (frame.width - optionWidth) / 2 - 3
        if start + barWidth > bounds.width - 2 { start = bounds.width - 2 - barWidth }
        if start < 2 { start = 2 }
        state.alternatesStart = start
        state.optionWidth = optionWidth
        state.phase = .alternates
        state.selectedAlternate = alternateIndex(for: state, x: state.last.x)

        let rect = CGRect(x: start, y: frame.minY + 2 - (popupHeight + 6), width: barWidth, height: popupHeight + 6)
        let popup = state.popup ?? dequeuePopup()
        state.popup = popup
        popup.showAlternates(
            options.map { engine.displayText(for: $0, caseSensitive: state.spec.isLetter) },
            selected: state.selectedAlternate,
            optionWidth: optionWidth,
            optionHeight: popupHeight,
            colors: colors,
            frame: convert(rect, to: overlayHost)
        )
        engine.keyFeedback(.modifier)
        refreshKey(state.keyID)
    }

    private func alternateIndex(for state: TouchState, x: CGFloat) -> Int {
        let raw = Int(((x - state.alternatesStart - 3) / state.optionWidth).rounded(.down))
        return min(max(raw, 0), max(state.spec.alternates.count - 1, 0))
    }

    // MARK: Trazo de la escritura deslizando

    private func beginTrail(at point: CGPoint) {
        guard configuration.showsGlideTrail else { return }
        trailLayer.removeAnimation(forKey: "fade")
        trailLayer.opacity = 1
        trailPoints = [point]
        updateTrailPath()
    }

    private func addTrailPoint(_ point: CGPoint) {
        guard configuration.showsGlideTrail, !trailPoints.isEmpty else { return }
        trailPoints.append(point)
        if trailPoints.count > 90 { trailPoints.removeFirst(trailPoints.count - 90) }
        updateTrailPath()
    }

    private func updateTrailPath() {
        guard let first = trailPoints.first else {
            trailLayer.path = nil
            return
        }
        let path = UIBezierPath()
        path.move(to: first)
        trailPoints.dropFirst().forEach { path.addLine(to: $0) }
        trailLayer.path = path.cgPath
    }

    private func fadeTrail() {
        guard !trailPoints.isEmpty else { return }
        trailPoints = []
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.25
        trailLayer.opacity = 0
        trailLayer.add(fade, forKey: "fade")
    }
}

/// Una tecla: fondo con sombra inferior como en Gboard, letra o icono y símbolo de la esquina.
final class KeyCapUIView: UIView {
    private let shadowView = UIView()
    private let capView = UIView()
    private let label = UILabel()
    private let hintLabel = UILabel()
    private let iconView = UIImageView()
    private var iconKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        for view in [shadowView, capView] {
            view.layer.cornerRadius = 7
            view.layer.cornerCurve = .continuous
            addSubview(view)
        }
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.baselineAdjustment = .alignCenters
        addSubview(label)
        addSubview(hintLabel)
        iconView.contentMode = .center
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cap = bounds.insetBy(dx: 3, dy: 4)
        capView.frame = cap
        shadowView.frame = cap.offsetBy(dx: 0, dy: 1)
        label.frame = bounds.insetBy(dx: 5, dy: 0)
        iconView.frame = bounds
        layoutHint()
    }

    private func layoutHint() {
        guard !hintLabel.isHidden else { return }
        hintLabel.sizeToFit()
        hintLabel.frame.origin = CGPoint(x: bounds.maxX - 8 - hintLabel.bounds.width, y: 6)
    }

    func setCap(fill: UIColor, shadow: UIColor?) {
        if capView.backgroundColor != fill { capView.backgroundColor = fill }
        shadowView.isHidden = shadow == nil
        if let shadow, shadowView.backgroundColor != shadow { shadowView.backgroundColor = shadow }
    }

    func setText(_ text: String, font: UIFont, color: UIColor) {
        iconView.isHidden = true
        label.isHidden = false
        if label.attributedText != nil, label.text != text { label.attributedText = nil }
        if label.text != text { label.text = text }
        if label.font != font { label.font = font }
        if label.textColor != color { label.textColor = color }
    }

    func hideHint() {
        hintLabel.isHidden = true
    }

    func setHint(_ hint: String?, font: UIFont, color: UIColor) {
        hintLabel.isHidden = hint == nil
        guard let hint else { return }
        let changed = hintLabel.text != hint || hintLabel.font != font
        if hintLabel.text != hint { hintLabel.text = hint }
        if hintLabel.font != font { hintLabel.font = font }
        if hintLabel.textColor != color { hintLabel.textColor = color }
        if changed { layoutHint() }
    }

    func setIcon(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight, color: UIColor) {
        label.isHidden = true
        hintLabel.isHidden = true
        iconView.isHidden = false
        let key = "\(name)-\(pointSize)-\(weight.rawValue)"
        if key != iconKey {
            iconKey = key
            iconView.image = UIImage(
                systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            )
        }
        if iconView.tintColor != color { iconView.tintColor = color }
    }

    /// Barra espaciadora mientras mueve el cursor: ‹ I › en el color de acento.
    func setCursorSymbols(color: UIColor) {
        iconView.isHidden = true
        hintLabel.isHidden = true
        label.isHidden = false
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let text = NSMutableAttributedString()
        for (index, name) in ["chevron.left", "character.cursor.ibeam", "chevron.right"].enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "      ")) }
            if let image = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal) {
                text.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            }
        }
        label.attributedText = text
    }
}

/// Ventana sobre la tecla pulsada: la letra ampliada o la fila de caracteres alternativos.
final class KeyPopupUIView: UIView {
    private var labels: [UILabel] = []
    private let selection = UIView()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        selection.layer.cornerRadius = 6
        selection.layer.cornerCurve = .continuous
        addSubview(selection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    private func prepareLabels(_ count: Int) {
        while labels.count < count {
            let label = UILabel()
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            addSubview(label)
            labels.append(label)
        }
        for (index, label) in labels.enumerated() {
            label.isHidden = index >= count
        }
    }

    private func place(in frame: CGRect, background: UIColor) {
        self.frame = frame
        backgroundColor = background
        // Con la forma de la sombra ya calculada, iOS no tiene que deducirla en cada fotograma.
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 10).cgPath
    }

    func showPreview(_ text: String, font: UIFont, colors: KeyGridColors, frame: CGRect) {
        place(in: frame, background: colors.popup)
        selection.isHidden = true
        prepareLabels(1)
        let label = labels[0]
        label.text = text
        label.font = font
        label.textColor = colors.text
        label.frame = bounds
    }

    func showAlternates(
        _ options: [String],
        selected: Int,
        optionWidth: CGFloat,
        optionHeight: CGFloat,
        colors: KeyGridColors,
        frame: CGRect
    ) {
        place(in: frame, background: colors.popup)
        prepareLabels(options.count)
        for (index, option) in options.enumerated() {
            let label = labels[index]
            label.text = option
            label.font = .systemFont(ofSize: option.count > 2 ? 15 : 22)
            label.frame = CGRect(x: 3 + CGFloat(index) * optionWidth, y: 3, width: optionWidth, height: optionHeight)
        }
        selection.isHidden = false
        selection.backgroundColor = colors.accent
        select(selected, colors: colors)
    }

    func select(_ index: Int, colors: KeyGridColors) {
        let visible = labels.filter { !$0.isHidden }
        guard visible.indices.contains(index) else { return }
        selection.frame = visible[index].frame
        for (offset, label) in visible.enumerated() {
            label.textColor = offset == index ? colors.accentText : colors.text
        }
    }
}
