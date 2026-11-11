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
final class KeyboardPanelUIScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        var candidate: UIView? = view
        while let current = candidate, current !== self {
            if current is UISlider { return false }
            if current is UISwitch || current is UIButton {
                // Un arrastre vertical sobre un control desplaza el panel; el horizontal
                // sigue perteneciendo al interruptor. No se cancela el deslizador.
                let movement = panGestureRecognizer.translation(in: self)
                return abs(movement.y) > abs(movement.x)
            }
            candidate = current.superview
        }
        return super.touchesShouldCancel(in: view)
    }
}

@MainActor
final class KeyboardPanelScrollController<Content: View>: UIViewController {
    let scrollView = KeyboardPanelUIScrollView()
    private let contentController: UIHostingController<Content>
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
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.isDirectionalLockEnabled = true
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
