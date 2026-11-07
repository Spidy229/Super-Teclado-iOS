import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// En iOS 27 los gestos de SwiftUI (botones, `DragGesture`, toques) pueden recibir el primer
// aviso del dedo hasta ~0,75 s tarde: la tecla no se ilumina ni vibra y la acción llega al
// levantar el dedo o un segundo después. Otros teclados (KeyboardKit, azooKey) lo resolvieron
// igual: el toque lo recibe un reconocedor de gestos de UIKit (4-9 ms), no SwiftUI.

/// Reconocedor que avisa en cuanto toca el dedo, se mueve, se levanta o se cancela.
/// - `startsImmediately`: para teclas (borrar, flechas…): se queda el toque desde el principio.
/// - Si no, se comporta como un toque: si el dedo se desplaza, deja paso al desplazamiento de
///   la lista que lo contiene.
final class InstantTouchRecognizer: UIGestureRecognizer {
    var startsImmediately = false
    var longPressDuration: Double?
    var onDown: () -> Void = {}
    var onMove: (CGSize) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onLongPress: (() -> Void)?
    var onEnd: () -> Void = {}

    private weak var tracked: UITouch?
    private var start: CGPoint = .zero
    private var longPressFired = false
    private var longPressTask: Task<Void, Never>?
    /// Desplazamiento a partir del cual un toque deja de serlo (y se cede a la lista).
    private static let tapSlop: CGFloat = 12

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where touch !== tracked {
            guard tracked == nil else {
                // Solo se sigue un dedo; los demás van a otras teclas.
                ignore(touch, for: event)
                continue
            }
            tracked = touch
            start = touch.location(in: view)
            longPressFired = false
            if startsImmediately { state = .began }
            onDown()
            scheduleLongPress()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        let point = tracked.location(in: view)
        let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
        if startsImmediately {
            state = .changed
            onMove(translation)
        } else if hypot(translation.width, translation.height) > Self.tapSlop {
            // Se está desplazando la lista: no es un toque.
            finish(tapped: false)
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        finish(tapped: !longPressFired)
        state = startsImmediately ? .ended : .recognized
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        finish(tapped: false)
        // Un toque que no había empezado no se puede «cancelar»: falla.
        state = startsImmediately ? .cancelled : .failed
    }

    override func reset() {
        super.reset()
        // Si iOS reinicia el reconocedor con el dedo aún dentro, se suelta sin acción.
        if tracked != nil { finish(tapped: false) }
    }

    private func finish(tapped: Bool) {
        longPressTask?.cancel()
        longPressTask = nil
        guard tracked != nil else { return }
        tracked = nil
        onEnd()
        if tapped { onTap() }
    }

    private func scheduleLongPress() {
        longPressTask?.cancel()
        guard let duration = longPressDuration, onLongPress != nil else { return }
        longPressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard let self, !Task.isCancelled, self.tracked != nil else { return }
            self.longPressFired = true
            self.onLongPress?()
        }
    }
}

/// El reconocedor anterior, para usarlo en SwiftUI con `.gesture(...)`.
struct InstantTouchGesture: UIGestureRecognizerRepresentable {
    var startsImmediately = false
    var longPressDuration: Double?
    var onDown: () -> Void = {}
    var onMove: (CGSize) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onLongPress: (() -> Void)?
    var onEnd: () -> Void = {}

    func makeUIGestureRecognizer(context: Context) -> InstantTouchRecognizer {
        let recognizer = InstantTouchRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: InstantTouchRecognizer, context: Context) {
        configure(recognizer)
    }

    func handleUIGestureRecognizerAction(_ recognizer: InstantTouchRecognizer, context: Context) {}

    private func configure(_ recognizer: InstantTouchRecognizer) {
        recognizer.startsImmediately = startsImmediately
        recognizer.longPressDuration = longPressDuration
        recognizer.onDown = onDown
        recognizer.onMove = onMove
        recognizer.onTap = onTap
        recognizer.onLongPress = onLongPress
        recognizer.onEnd = onEnd
    }
}

/// Botón que responde al instante (sustituye a `Button` dentro del teclado). Se atenúa
/// mientras se pulsa y, si se indica, vibra al tocar como una tecla.
struct InstantButton<Label: View>: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.isEnabled) private var isEnabled
    var feedback: KeyFeedbackKind?
    let action: () -> Void
    let label: Label

    @State private var isPressed = false

    /// Mismo uso que `Button`: `InstantButton { acción } label: { … }`.
    init(feedback: KeyFeedbackKind? = nil, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.feedback = feedback
        self.action = action
        self.label = label()
    }

    var body: some View {
        label
            .opacity(isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
            .gesture(
                InstantTouchGesture(
                    onDown: {
                        guard isEnabled else { return }
                        isPressed = true
                        if let feedback { engine.keyFeedback(feedback) }
                    },
                    onTap: {
                        guard isEnabled else { return }
                        action()
                    },
                    onEnd: { isPressed = false }
                )
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isEnabled { action() }
            }
    }
}

extension InstantButton where Label == Text {
    init(_ title: String, feedback: KeyFeedbackKind? = nil, action: @escaping () -> Void) {
        self.init(feedback: feedback, action: action) { Text(title) }
    }
}
