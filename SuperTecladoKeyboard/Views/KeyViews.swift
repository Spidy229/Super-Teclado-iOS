import SwiftUI

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

/// Palabra que se va reconociendo al escribir deslizando, para mostrarla en la barra. El trazo
/// lo dibuja la propia cuadrícula de teclas.
@MainActor
final class GlideTrail: ObservableObject {
    @Published var preview: String?
}
