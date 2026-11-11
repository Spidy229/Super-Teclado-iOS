import SwiftUI
import UIKit
import XCTest
@testable import SuperTeclado

/// Monta la representación SwiftUI real en una ventana; no sustituye por un mock la búsqueda
/// o conexión del scroll. La entrega física de toques en iOS 27 sigue requiriendo el iPhone.
final class KeyboardPanelScrollIntegrationTests: XCTestCase {
    @MainActor
    func testHostedPanelConnectsItsOwnScrollAndLaysOutChangingContent() async throws {
        let recorder = EnvironmentRecorder()
        let host = UIHostingController(rootView: panel(height: 2_000, revision: "primera", recorder: recorder))
        let window = makeWindow(host: host)
        defer { window.isHidden = true; window.rootViewController = nil }

        await waitUntil { (findScroll(in: host.view)?.contentSize.height ?? 0) > 1_800 }
        let scroll = try XCTUnwrap(findScroll(in: host.view))
        XCTAssertGreaterThan(scroll.bounds.width, 200)
        XCTAssertGreaterThan(scroll.bounds.height, 100)
        XCTAssertFalse(scroll.delaysContentTouches)
        XCTAssertTrue(scroll.canCancelContentTouches)
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
        XCTAssertEqual(recorder.colorScheme, .dark)
        XCTAssertEqual(recorder.revision, "primera")

        scroll.setContentOffset(CGPoint(x: 0, y: 150), animated: false)
        host.rootView = panel(height: 2_600, revision: "actualizada", recorder: recorder)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await waitUntil { recorder.revision == "actualizada" && scroll.contentSize.height > 2_400 }

        XCTAssertTrue(findScroll(in: host.view) === scroll)
        XCTAssertEqual(scroll.contentOffset.y, 150, accuracy: 1)
        XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
        XCTAssertEqual(recorder.colorScheme, .dark)
    }

    @MainActor
    func testRemovingHostedPanelRestoresTouchesAndRemovesOnlyItsObserver() async throws {
        let recorder = EnvironmentRecorder()
        let host = UIHostingController(rootView: panel(height: 2_000, revision: "visible", recorder: recorder))
        let window = makeWindow(host: host)
        defer { window.isHidden = true; window.rootViewController = nil }
        await waitUntil { findScroll(in: host.view) != nil }
        let scroll = try XCTUnwrap(findScroll(in: host.view))
        let attached = Set((scroll.gestureRecognizers ?? []).map(ObjectIdentifier.init))
        let pan = scroll.panGestureRecognizer
        XCTAssertFalse(scroll.delaysContentTouches)

        host.rootView = AnyView(EmptyView())
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await waitUntil { scroll.delaysContentTouches }

        let remaining = Set((scroll.gestureRecognizers ?? []).map(ObjectIdentifier.init))
        XCTAssertEqual(remaining.count, attached.count - 1)
        XCTAssertTrue(remaining.isSubset(of: attached))
        XCTAssertTrue(remaining.contains(ObjectIdentifier(pan)))
        XCTAssertTrue(pan.isEnabled)
        XCTAssertTrue(scroll.canCancelContentTouches)
    }

    @MainActor
    func testVerticalScrollCanCancelButtonsWithoutStealingHorizontalControls() async {
        let scroll = ControlledPanScrollView()
        let button = UIButton(type: .system)
        let toggle = UISwitch()
        let slider = UISlider()
        let toggleChild = UIView()
        toggle.addSubview(toggleChild)
        [button, toggle, slider].forEach { scroll.addSubview($0) }

        XCTAssertFalse(scroll.touchesShouldCancel(in: button))
        XCTAssertFalse(scroll.touchesShouldCancel(in: toggleChild))
        XCTAssertFalse(scroll.touchesShouldCancel(in: slider))

        scroll.motion = (CGPoint(x: 2, y: 30), .zero)
        XCTAssertTrue(scroll.touchesShouldCancel(in: button))
        XCTAssertTrue(scroll.touchesShouldCancel(in: toggleChild))
        XCTAssertFalse(scroll.touchesShouldCancel(in: slider))

        scroll.motion = (CGPoint(x: 30, y: 2), .zero)
        XCTAssertFalse(scroll.touchesShouldCancel(in: button))
        XCTAssertFalse(scroll.touchesShouldCancel(in: toggleChild))
        XCTAssertFalse(scroll.touchesShouldCancel(in: slider))

        // En el primer instante del pan, UIKit puede dar traslación cero pero ya conoce
        // su velocidad. Se mantiene la misma separación entre scroll y controles.
        scroll.motion = (.zero, CGPoint(x: 10, y: 300))
        XCTAssertTrue(scroll.touchesShouldCancel(in: button))
        XCTAssertTrue(scroll.touchesShouldCancel(in: toggleChild))
        XCTAssertFalse(scroll.touchesShouldCancel(in: slider))

        scroll.motion = (.zero, CGPoint(x: 300, y: 10))
        XCTAssertFalse(scroll.touchesShouldCancel(in: button))
        XCTAssertFalse(scroll.touchesShouldCancel(in: toggleChild))
        XCTAssertFalse(scroll.touchesShouldCancel(in: slider))
    }

    @MainActor
    private func panel(height: CGFloat, revision: String, recorder: EnvironmentRecorder) -> AnyView {
        AnyView(KeyboardPanelScrollView {
            PanelFixture(height: height, revision: revision)
                .environmentObject(recorder)
                .environment(\.colorScheme, .dark)
        })
    }

    @MainActor
    private func makeWindow(host: UIViewController) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }

    @MainActor
    private func findScroll(in view: UIView) -> KeyboardPanelUIScrollView? {
        if let scroll = view as? KeyboardPanelUIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "La jerarquía del panel no llegó al estado esperado.", file: file, line: line)
    }
}

@MainActor
private final class ControlledPanScrollView: KeyboardPanelUIScrollView {
    var motion: (translation: CGPoint, velocity: CGPoint) = (.zero, .zero)

    override var controlPanMotion: (translation: CGPoint, velocity: CGPoint) { motion }
}

@MainActor
private final class EnvironmentRecorder: ObservableObject {
    var colorScheme: ColorScheme?
    var revision: String?
}

private struct PanelFixture: View {
    @EnvironmentObject private var recorder: EnvironmentRecorder
    @Environment(\.colorScheme) private var colorScheme
    @State private var enabled = false
    @State private var strength = 0.6
    let height: CGFloat
    let revision: String

    var body: some View {
        VStack {
            Text(revision)
            ScrollView(.horizontal) {
                HStack { ForEach(0..<10) { Text("Opción \($0)").frame(width: 100) } }
            }
            Toggle("Activado", isOn: $enabled)
            Slider(value: $strength)
            Color.clear.frame(height: height)
            EnvironmentProbe(recorder: recorder, colorScheme: colorScheme, revision: revision)
                .frame(height: 1)
        }
    }
}

private struct EnvironmentProbe: UIViewRepresentable {
    let recorder: EnvironmentRecorder
    let colorScheme: ColorScheme
    let revision: String

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        recorder.colorScheme = colorScheme
        recorder.revision = revision
    }
}
