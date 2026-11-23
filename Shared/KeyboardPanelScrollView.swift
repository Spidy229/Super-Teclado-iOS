import SwiftUI
import UIKit

/// El panel controla su UIScrollView directamente, sin buscar vistas privadas de SwiftUI.
/// El contenido sigue siendo SwiftUI; el arrastre, la inercia y sus toques pertenecen a UIKit.
struct KeyboardPanelScrollView<Content: View>: UIViewControllerRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> KeyboardPanelScrollController<Content> {
        KeyboardPanelScrollController(content: content)
    }

    func updateUIViewController(_ controller: KeyboardPanelScrollController<Content>, context: Context) {
        controller.updateContent(content)
    }

    static func dismantleUIViewController(_ controller: KeyboardPanelScrollController<Content>, coordinator: ()) {
        controller.disconnectTouches()
    }
}

@MainActor
class KeyboardPanelUIScrollView: UIScrollView {
    /// Separar la lectura de UIKit permite comprobar la decisión sin fabricar UITouch.
    var controlPanMotion: (translation: CGPoint, velocity: CGPoint) {
        (panGestureRecognizer.translation(in: self), panGestureRecognizer.velocity(in: self))
    }

    private func isHorizontalInteractiveControl(_ view: UIView) -> Bool {
        var candidate: UIView? = view
        while let current = candidate, current !== self {
            if current is UISlider || current is UISwitch { return true }
            if let nestedScroll = current as? UIScrollView, nestedScroll.isScrollEnabled {
                return true
            }
            candidate = current.superview
        }
        return false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let location = panGestureRecognizer.location(in: self)
        if let hit = hitTest(location, with: nil), isHorizontalInteractiveControl(hit) {
            let motion = controlPanMotion
            let movement = motion.velocity == .zero ? motion.translation : motion.velocity
            // Solo ceder a un deslizador, interruptor o barra de chips desplazable cuando el
            // gesto es claramente horizontal; cualquier arrastre vertical o diagonal desplaza la lista.
            if abs(movement.x) > abs(movement.y) * 1.2 {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        var candidate: UIView? = view
        while let current = candidate, current !== self {
            if current is UISlider {
                let motion = controlPanMotion
                let movement = motion.translation == .zero ? motion.velocity : motion.translation
                return abs(movement.y) > abs(movement.x) * 1.2
            }
            if current is UISwitch {
                // Solo mantener el interruptor en un deslizamiento claramente horizontal; el resto
                // (incluido movimiento inicial cero o un arco natural del pulgar) desplaza el panel.
                let motion = controlPanMotion
                let movement = motion.translation == .zero ? motion.velocity : motion.translation
                if abs(movement.x) > abs(movement.y) * 1.2 { return false }
                return true
            }
            if current is UIControl {
                // Botones y chips de toque nunca deben bloquear el desplazamiento vertical.
                return true
            }
            candidate = current.superview
        }
        return super.touchesShouldCancel(in: view)
    }
}

/// En el panel compacto de ajustes la lista sigue el dedo hasta que se levanta.
@MainActor
private final class SettingsDragDelegate: NSObject, UIScrollViewDelegate {
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        targetContentOffset.pointee = scrollView.contentOffset
    }
}

@MainActor
final class KeyboardPanelScrollController<Content: View>: UIViewController {
    let scrollView = KeyboardPanelUIScrollView()
    private let contentController: UIHostingController<Content>
    private let dragDelegate = SettingsDragDelegate()
    private let touchScope = KeyboardScrollTouchScope()

    init(content: Content) {
        contentController = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func loadView() {
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.backgroundColor = UIColor(white: 0, alpha: 0.01)
        scrollView.delegate = dragDelegate
        scrollView.bounces = false
        scrollView.isDirectionalLockEnabled = false
        scrollView.canCancelContentTouches = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false

        contentController.sizingOptions = [.intrinsicContentSize]
        contentController.safeAreaRegions = []
        contentController.view.backgroundColor = .clear
        addChild(contentController)
        let contentView = contentController.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        contentController.didMove(toParent: self)
        touchScope.attach(to: scrollView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        touchScope.attach(to: scrollView)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        disconnectTouches()
    }

    func updateContent(_ content: Content) {
        contentController.rootView = content
        guard isViewLoaded else { return }
        contentController.view.invalidateIntrinsicContentSize()
        // No se reasigna el offset ni se reconstruye el scroll al cambiar una preferencia:
        // UIKit conserva la posición y cualquier arrastre o inercia que siga en curso.
    }

    func disconnectTouches() {
        touchScope.detach()
    }
}
