import SwiftUI
import UIKit

/// Sonda sin hit testing, puesta en el contenido del ScrollView exterior de ⚙︎. Solo configura
/// su ancestro UIScrollView más cercano; no toca la ventana, la cuadrícula ni las listas hijas.
struct SettingsScrollTouchScope: UIViewRepresentable {
    func makeUIView(context: Context) -> SettingsScrollTouchProbe {
        SettingsScrollTouchProbe()
    }

    func updateUIView(_ view: SettingsScrollTouchProbe, context: Context) {
        view.connectIfPossible()
    }

    static func dismantleUIView(_ view: SettingsScrollTouchProbe, coordinator: ()) {
        view.disconnect()
    }
}

final class SettingsScrollTouchProbe: UIView {
    private let scope = KeyboardScrollTouchScope()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        connectIfPossible()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { disconnect() } else { connectIfPossible() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        connectIfPossible()
    }

    func connectIfPossible() {
        guard window != nil else {
            disconnect()
            return
        }
        var candidate = superview
        while let current = candidate {
            if let scroll = current as? UIScrollView {
                scope.attach(to: scroll)
                return
            }
            candidate = current.superview
        }
        disconnect()
    }

    func disconnect() { scope.detach() }
}
