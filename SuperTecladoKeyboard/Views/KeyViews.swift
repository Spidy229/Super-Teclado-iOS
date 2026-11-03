import SwiftUI

/// Tecla de carácter con ventana emergente al pulsar y caracteres alternativos con pulsación larga.
struct CharacterKeyView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let value: String
    let hint: String?
    let alternates: [String]
    let caseSensitive: Bool
    let size: CGSize
    /// Esquina superior izquierda de la tecla en la cuadrícula (para el trazo deslizado).
    let origin: CGPoint
    let gridSize: CGSize

    @State private var isPressed = false
    @State private var isGliding = false
    @State private var showsAlternates = false
    @State private var selectedIndex = 0
    @State private var lastTouchX: CGFloat = 0
    @State private var longPressTask: Task<Void, Never>?

    private var displayValue: String { engine.displayText(for: value, caseSensitive: caseSensitive) }
    private var popupHeight: CGFloat { max(36, size.height - 8) }
    private var optionWidth: CGFloat { max(30, min(44, size.width - 6)) }
    private var fontSize: CGFloat { min(25, size.height * 0.46) * (value.count > 2 ? 0.7 : 1) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            KeyCapView(
                fill: palette.key,
                isPressed: isPressed && !engine.preferences.keyPopups
            )
            Text(displayValue)
                .font(.system(size: fontSize))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let hint, engine.preferences.longPressSymbols {
                Text(hint)
                    .font(.system(size: max(9, size.height * 0.19), weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 6)
                    .padding(.trailing, 8)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .overlay(alignment: .bottomLeading) { popup }
        .zIndex(isPressed ? 10 : 0)
        .gesture(pressGesture)
        .accessibilityElement()
        .accessibilityLabel(displayValue)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                lastTouchX = gesture.location.x
                if isGliding {
                    engine.extendGlide(to: gridPoint(gesture.location))
                    return
                }
                if !isPressed {
                    isPressed = true
                    engine.keyFeedback(.character)
                    scheduleLongPress()
                }
                if showsAlternates {
                    selectedIndex = alternateIndex(at: gesture.location.x)
                } else if caseSensitive, engine.canGlide,
                          GlideDecoder.distance(gesture.startLocation, gesture.location) > max(18, size.width * 0.6) {
                    // El dedo ha salido de la tecla: empieza la escritura deslizando.
                    longPressTask?.cancel()
                    longPressTask = nil
                    isPressed = false
                    isGliding = true
                    engine.beginGlide(at: gridPoint(gesture.startLocation), gridSize: gridSize)
                    engine.extendGlide(to: gridPoint(gesture.location))
                }
            }
            .onEnded { _ in
                longPressTask?.cancel()
                longPressTask = nil
                if isGliding {
                    isGliding = false
                    // Un desliz corto al teclear rápido cuenta como pulsación normal.
                    if !engine.endGlide() { engine.insertCharacter(value, caseSensitive: caseSensitive) }
                    return
                }
                if showsAlternates {
                    if alternates.indices.contains(selectedIndex) {
                        engine.insertCharacter(alternates[selectedIndex], caseSensitive: caseSensitive)
                    }
                } else {
                    engine.insertCharacter(value, caseSensitive: caseSensitive)
                }
                isPressed = false
                showsAlternates = false
                selectedIndex = 0
            }
    }

    private func scheduleLongPress() {
        guard !alternates.isEmpty else { return }
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(engine.preferences.longPressDelay))
            guard !Task.isCancelled, isPressed, !isGliding else { return }
            showsAlternates = true
            selectedIndex = alternateIndex(at: lastTouchX)
            engine.keyFeedback(.modifier)
        }
    }

    private func gridPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + location.x, y: origin.y + location.y)
    }

    /// Posición horizontal de la barra de alternativas respecto al borde izquierdo de la tecla.
    private var alternatesStart: CGFloat {
        let barWidth = CGFloat(alternates.count) * optionWidth + 6
        var start = (size.width - optionWidth) / 2 - 3
        if origin.x + start + barWidth > gridSize.width - 2 {
            start = gridSize.width - 2 - barWidth - origin.x
        }
        if origin.x + start < 2 { start = 2 - origin.x }
        return start
    }

    private func alternateIndex(at x: CGFloat) -> Int {
        let raw = Int(((x - alternatesStart - 3) / optionWidth).rounded(.down))
        return min(max(raw, 0), max(alternates.count - 1, 0))
    }

    @ViewBuilder
    private var popup: some View {
        if showsAlternates {
            HStack(spacing: 0) {
                ForEach(Array(alternates.enumerated()), id: \.offset) { index, option in
                    Text(engine.displayText(for: option, caseSensitive: caseSensitive))
                        .font(.system(size: option.count > 2 ? 15 : 22))
                        .foregroundStyle(index == selectedIndex ? palette.accentText : palette.text)
                        .frame(width: optionWidth, height: popupHeight)
                        .background(
                            index == selectedIndex ? palette.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
            }
            .padding(3)
            .background(palette.popup, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .offset(x: alternatesStart, y: -(size.height - 2))
            .allowsHitTesting(false)
        } else if isPressed && engine.preferences.keyPopups {
            Text(displayValue)
                .font(.system(size: min(34, fontSize * 1.35)))
                .foregroundStyle(palette.text)
                .frame(width: size.width, height: popupHeight)
                .background(palette.popup, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .offset(y: -(size.height - 2))
                .allowsHitTesting(false)
        }
    }
}

/// Tecla de función que reacciona al tocar (mayúsculas, ?123, intro…).
struct FunctionKeyView<Label: View>: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let size: CGSize
    var fill: Color?
    var alwaysFilled = false
    var feedback: KeyFeedbackKind = .modifier
    var accessibilityText: String
    let action: () -> Void
    let label: Label

    @State private var isPressed = false

    init(
        size: CGSize,
        fill: Color? = nil,
        alwaysFilled: Bool = false,
        feedback: KeyFeedbackKind = .modifier,
        accessibilityText: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.size = size
        self.fill = fill
        self.alwaysFilled = alwaysFilled
        self.feedback = feedback
        self.accessibilityText = accessibilityText
        self.action = action
        self.label = label()
    }

    var body: some View {
        ZStack {
            KeyCapView(fill: fill ?? palette.specialKey, isPressed: isPressed, alwaysFilled: alwaysFilled)
            label
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    engine.keyFeedback(feedback)
                }
                .onEnded { _ in
                    isPressed = false
                    action()
                }
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { action() }
    }
}

/// Borrar: repite al mantener y borra palabras completas al deslizar hacia la izquierda.
struct DeleteKeyView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let size: CGSize
    var fill: Color?

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var swipeSteps = 0

    var body: some View {
        ZStack {
            KeyCapView(fill: fill ?? palette.specialKey, isPressed: isPressed)
            Image(systemName: isPressed ? "delete.left.fill" : "delete.left")
                .font(.system(size: min(21, size.height * 0.4)))
                .foregroundStyle(palette.text)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isPressed {
                        isPressed = true
                        engine.keyFeedback(.delete)
                        engine.deleteBackward()
                        startRepeating()
                    }
                    let steps = Int(-gesture.translation.width / 24)
                    if steps > 0 {
                        repeatTask?.cancel()
                        while swipeSteps < steps {
                            swipeSteps += 1
                            engine.deleteWordBackward()
                            engine.keyFeedback(.delete)
                        }
                    }
                }
                .onEnded { _ in
                    repeatTask?.cancel()
                    repeatTask = nil
                    isPressed = false
                    swipeSteps = 0
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Borrar")
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { engine.deleteBackward() }
    }

    private func startRepeating() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            var count = 0
            while !Task.isCancelled {
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
}

/// Tecla que repite su acción mientras se mantiene (flechas del panel de edición).
struct RepeatingKeyView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let size: CGSize
    let symbol: String
    let title: String?
    let accessibilityText: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            KeyCapView(fill: palette.key, isPressed: isPressed, alwaysFilled: true)
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                if let title { Text(title).font(.system(size: 11, weight: .medium)) }
            }
            .foregroundStyle(palette.text)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    engine.keyFeedback(.modifier)
                    action()
                    repeatTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(420))
                        while !Task.isCancelled {
                            action()
                            try? await Task.sleep(for: .milliseconds(80))
                        }
                    }
                }
                .onEnded { _ in
                    repeatTask?.cancel()
                    repeatTask = nil
                    isPressed = false
                }
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAction { action() }
    }
}

/// Barra espaciadora: toca para un espacio, desliza para mover el cursor.
struct SpaceKeyView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let size: CGSize

    @State private var isPressed = false
    @State private var cursorMode = false
    @State private var lastStep = 0

    var body: some View {
        ZStack {
            KeyCapView(fill: palette.key, isPressed: isPressed && !cursorMode)
            if cursorMode {
                HStack(spacing: 18) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "character.cursor.ibeam")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
            } else {
                Text("Español")
                    .font(.system(size: min(15, size.height * 0.3)))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isPressed {
                        isPressed = true
                        engine.keyFeedback(.character)
                    }
                    let width = gesture.translation.width
                    let step = Int(width / 9)
                    if !cursorMode, abs(width) > 16 {
                        cursorMode = true
                        engine.isCursorMode = true
                        lastStep = step
                    }
                    if cursorMode, step != lastStep {
                        engine.moveCursor(by: step - lastStep)
                        engine.keyFeedback(.character)
                        lastStep = step
                    }
                }
                .onEnded { _ in
                    if !cursorMode { engine.insertSpace() }
                    isPressed = false
                    cursorMode = false
                    engine.isCursorMode = false
                    lastStep = 0
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Espacio")
        .accessibilityAddTraits(.isKeyboardKey)
        .accessibilityAction { engine.insertSpace() }
    }
}

/// Estela azul que sigue al dedo al escribir deslizando, como en Gboard.
@MainActor
final class GlideTrail: ObservableObject {
    @Published private(set) var points: [CGPoint] = []
    @Published private(set) var isFading = false
    private var fadeTask: Task<Void, Never>?

    func begin(at point: CGPoint) {
        fadeTask?.cancel()
        isFading = false
        points = [point]
    }

    func add(_ point: CGPoint) {
        points.append(point)
        if points.count > 240 { points.removeFirst(points.count - 240) }
    }

    func finish() {
        guard !points.isEmpty else { return }
        isFading = true
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard let self, !Task.isCancelled else { return }
            self.points = []
            self.isFading = false
        }
    }
}

struct GlideTrailView: View {
    @ObservedObject var trail: GlideTrail
    let color: Color

    var body: some View {
        let points = Array(trail.points.suffix(90))
        Canvas { context, _ in
            guard points.count > 1 else { return }
            var path = Path()
            path.addLines(points)
            context.stroke(
                path,
                with: .color(color.opacity(0.75)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )
        }
        .opacity(trail.isFading ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: trail.isFading)
        .allowsHitTesting(false)
    }
}
