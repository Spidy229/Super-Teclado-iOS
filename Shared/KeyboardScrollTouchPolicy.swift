import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reglas de los botones de panel: el movimiento se mide fuera del contenido desplazable y
/// solo se permite convivir con el pan de una lista que realmente contiene el botón.
@MainActor
enum KeyboardScrollTouchPolicy {
    static let tapSlop: CGFloat = 12

    static func referenceView(for view: UIView?) -> UIView? {
        guard let view else { return nil }
        if let window = view.window { return window }
        var root = view
        while let parent = root.superview { root = parent }
        return root
    }

    static func movedBeyondTap(from start: CGPoint, to point: CGPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) > tapSlop
    }

    static func isAncestorScrollPan(_ recognizer: UIGestureRecognizer, of view: UIView?) -> Bool {
        var candidate = view
        while let current = candidate {
            if let scroll = current as? UIScrollView, recognizer === scroll.panGestureRecognizer {
                return true
            }
            candidate = current.superview
        }
        return false
    }

    static func stopDecelerationIfNeeded(in scroll: UIScrollView) {
        guard scroll.isDecelerating, !scroll.isDragging else { return }
        scroll.setContentOffset(scroll.contentOffset, animated: false)
    }
}

/// Configuración con propietario explícito. Si SwiftUI monta dos sondas durante un cambio,
/// comparten el observador y la configuración original solo se restaura al retirar la última.
@MainActor
final class KeyboardScrollTouchScope {
    private weak var scrollView: UIScrollView?
    private var observer: ScrollDecelerationStopRecognizer?

    func attach(to scroll: UIScrollView) {
        guard scrollView !== scroll else { return }
        detach()
        let observer: ScrollDecelerationStopRecognizer
        if let installed = scroll.gestureRecognizers?.compactMap({ $0 as? ScrollDecelerationStopRecognizer }).first {
            observer = installed
        } else {
            observer = ScrollDecelerationStopRecognizer(scrollView: scroll)
            scroll.addGestureRecognizer(observer)
        }
        observer.owners += 1
        scroll.delaysContentTouches = false
        scrollView = scroll
        self.observer = observer
    }

    func detach() {
        guard let observer else { return }
        observer.owners -= 1
        if observer.owners == 0, let scroll = scrollView {
            scroll.removeGestureRecognizer(observer)
            scroll.delaysContentTouches = observer.originalDelaysContentTouches
        }
        self.observer = nil
        scrollView = nil
    }
}

/// Solo observa el comienzo: detiene la inercia, falla y deja los controles y el pan decidir
/// qué hacer con el mismo dedo. No reconoce pulsaciones ni ejecuta acciones del panel.
private final class ScrollDecelerationStopRecognizer: UIGestureRecognizer {
    weak var scrollView: UIScrollView?
    let originalDelaysContentTouches: Bool
    var owners = 0

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        originalDelaysContentTouches = scrollView.delaysContentTouches
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let scrollView { KeyboardScrollTouchPolicy.stopDecelerationIfNeeded(in: scrollView) }
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
