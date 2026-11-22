import UIKit
import UIKit.UIGestureRecognizerSubclass
import XCTest

final class KeyGridDeliveryTests: XCTestCase {
    @MainActor
    private final class Finger: UITouch {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    @MainActor
    private final class PhasedTouch: UITouch {
        var customPhase: UITouch.Phase
        init(phase: UITouch.Phase) {
            self.customPhase = phase
            super.init()
        }
        override var phase: UITouch.Phase { customPhase }
    }

    @MainActor
    func testOverlappingLettersThenBackspaceCommitOnceAndNextKeyStopsRepeat() async throws {
        let engine = KeyboardEngine()
        engine.panel = .clipboardSearch
        engine.preferences.keyPopups = false
        engine.preferences.sound = false
        engine.shift = .off
        let grid = KeyGridUIView(engine: engine)
        grid.frame = CGRect(x: 0, y: 0, width: 390, height: 224)
        grid.apply(KeyGridConfiguration(engine: engine), palette: .make(theme: .dark, systemIsDark: true))
        grid.layoutIfNeeded()

        func finger(on label: String) throws -> Finger {
            let cap = try XCTUnwrap(grid.subviews.first { $0.accessibilityLabel == label })
            let touch = Finger()
            touch.point = CGPoint(x: cap.frame.midX, y: cap.frame.midY)
            return touch
        }

        let a = try finger(on: "a")
        let s = try finger(on: "s")
        let delete = try finger(on: "Borrar")
        let d = try finger(on: "d")
        grid.touchesBegan([a], with: nil)
        grid.touchesBegan([s], with: nil)
        XCTAssertEqual(engine.searchQuery, "a")
        grid.touchesEnded([a], with: nil)
        grid.touchesBegan([delete], with: nil)
        XCTAssertEqual(engine.searchQuery, "a")
        grid.touchesEnded([s], with: nil)
        grid.touchesBegan([d], with: nil)
        grid.touchesEnded([d], with: nil)
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(engine.searchQuery, "ad")
        grid.touchesEnded([delete], with: nil)
        XCTAssertFalse(grid.hasActiveTouches)
    }

    @MainActor
    func testGridUsesNativeHitTestingAndPreservesHostGestureConfiguration() async throws {
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 250))
        window.rootViewController = root
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let gate = UITapGestureRecognizer()
        gate.delaysTouchesBegan = true
        gate.delaysTouchesEnded = true
        window.addGestureRecognizer(gate)
        let engine = KeyboardEngine()
        let grid = KeyGridUIView(engine: engine)
        root.view.frame = window.bounds
        grid.frame = CGRect(x: 0, y: 40, width: 390, height: 210)
        root.view.addSubview(grid)
        grid.apply(KeyGridConfiguration(engine: engine), palette: .make(theme: .dark, systemIsDark: true))
        grid.layoutIfNeeded()

        XCTAssertTrue(grid.isMultipleTouchEnabled)
        let recognizer = try XCTUnwrap(grid.gestureRecognizers?.first)
        XCTAssertEqual(grid.gestureRecognizers?.count, 1)
        XCTAssertFalse(recognizer.delaysTouchesBegan)
        XCTAssertFalse(recognizer.delaysTouchesEnded)
        XCTAssertFalse(recognizer.cancelsTouchesInView)
        XCTAssertFalse(recognizer.canPrevent(gate))
        XCTAssertFalse(recognizer.canBePrevented(by: gate))
        XCTAssertTrue(gate.delaysTouchesBegan)
        XCTAssertTrue(gate.delaysTouchesEnded)
        for point in [CGPoint(x: 2, y: 42), CGPoint(x: 195, y: 162), CGPoint(x: 388, y: 248)] {
            XCTAssertTrue(window.hitTest(point, with: nil) === grid)
        }
        XCTAssertFalse(window.hitTest(CGPoint(x: 20, y: 20), with: nil) === grid)
        grid.isHidden = true
        XCTAssertFalse(window.hitTest(CGPoint(x: 195, y: 162), with: nil) === grid)
    }

    @MainActor
    func testEveryPointAcrossGridIncludingGapsAndSafeAreaMarginsResolvesAndActivatesAKey() throws {
        let engine = KeyboardEngine()
        engine.panel = .clipboardSearch
        engine.preferences.keyPopups = false
        engine.preferences.sound = false
        engine.shift = .off
        let grid = KeyGridUIView(engine: engine)
        grid.frame = CGRect(x: 0, y: 0, width: 430, height: 246)
        grid.keyContentInsets = UIEdgeInsets(top: 0, left: 20, bottom: 22, right: 20)
        grid.apply(KeyGridConfiguration(engine: engine), palette: .make(theme: .glass, systemIsDark: true))
        grid.layoutIfNeeded()

        // Ningún punto dentro de la cuadrícula (márgenes seguros, bordes ni huecos entre teclas)
        // puede quedar sin tecla asignada ni fuera del hit-testing.
        var y: CGFloat = 0
        while y < grid.bounds.height {
            var x: CGFloat = 0
            while x < grid.bounds.width {
                let point = CGPoint(x: x, y: y)
                XCTAssertTrue(grid.hitTest(point, with: nil) === grid, "Hueco de hitTest en \(point)")
                XCTAssertNotNil(grid.resolvedKeyID(at: point), "Sin tecla en \(point)")
                x += 11
            }
            y += 11
        }
        for corner in [
            CGPoint(x: 0, y: 0),
            CGPoint(x: grid.bounds.width - 1, y: 0),
            CGPoint(x: 0, y: grid.bounds.height - 1),
            CGPoint(x: grid.bounds.width - 1, y: grid.bounds.height - 1)
        ] {
            XCTAssertTrue(grid.hitTest(corner, with: nil) === grid)
            XCTAssertNotNil(grid.resolvedKeyID(at: corner))
        }

        // Pulsar exactamente en la costura horizontal entre «a» y «s», en la costura vertical
        // entre «q» y «a», y en el margen izquierdo exterior siempre escribe una letra.
        let qCap = try XCTUnwrap(grid.subviews.first { $0.accessibilityLabel == "q" })
        let aCap = try XCTUnwrap(grid.subviews.first { $0.accessibilityLabel == "a" })
        let sCap = try XCTUnwrap(grid.subviews.first { $0.accessibilityLabel == "s" })
        let seamPoints = [
            CGPoint(x: (aCap.frame.maxX + sCap.frame.minX) / 2, y: aCap.frame.midY),
            CGPoint(x: qCap.frame.midX, y: (qCap.frame.maxY + aCap.frame.minY) / 2),
            CGPoint(x: 2, y: aCap.frame.midY)
        ]
        for point in seamPoints {
            let before = engine.searchQuery.count
            let tap = Finger()
            tap.point = point
            grid.touchesBegan([tap], with: nil)
            grid.touchesEnded([tap], with: nil)
            XCTAssertEqual(engine.searchQuery.count, before + 1, "No se activó ninguna tecla en \(point)")
        }
    }

    @MainActor
    func testActiveTouchIDsExcludeEndedAndCancelledTouches() {
        let began = PhasedTouch(phase: .began)
        let moved = PhasedTouch(phase: .moved)
        let stationary = PhasedTouch(phase: .stationary)
        let ended = PhasedTouch(phase: .ended)
        let cancelled = PhasedTouch(phase: .cancelled)

        let active = KeyGridUIView.activeTouchIDs(in: [began, moved, stationary, ended, cancelled])
        XCTAssertEqual(active, [ObjectIdentifier(began), ObjectIdentifier(moved), ObjectIdentifier(stationary)])
    }

    @MainActor
    func testPureUIKitSettingsPanelTogglesPreferencesAndClosesWithoutHostingController() {
        let engine = KeyboardEngine()
        engine.panel = .settings
        engine.preferences.autocorrect = true
        let panel = KeyboardSettingsPanelUIView(engine: engine)
        panel.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
        panel.apply(palette: .make(theme: .dark, systemIsDark: true), stripHeight: 44)
        panel.layoutIfNeeded()
        panel.scrollView.layoutIfNeeded()
        panel.longPressChips.setNeedsLayout()
        panel.longPressChips.layoutIfNeeded()

        XCTAssertTrue(panel.scrollView.delaysContentTouches)
        XCTAssertTrue(panel.scrollView.canCancelContentTouches)
        XCTAssertFalse(panel.scrollView.isDirectionalLockEnabled)
        XCTAssertEqual(panel.scrollView.decelerationRate, .fast)
        XCTAssertTrue(panel.hapticStyleChips.delaysContentTouches)
        XCTAssertTrue(panel.hapticStyleChips.touchesShouldCancel(in: UIButton()))
        XCTAssertFalse(panel.longPressChips.isScrollEnabled)
        XCTAssertTrue(panel.scrollView.touchesShouldCancel(in: panel.autocorrectSwitchRow.toggle))
        XCTAssertTrue(panel.autocorrectSwitchRow.toggle.isOn)

        panel.autocorrectSwitchRow.toggle.setOn(false, animated: false)
        panel.autocorrectSwitchRow.toggle.sendActions(for: .valueChanged)
        XCTAssertFalse(engine.preferences.autocorrect)

        panel.backButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(engine.panel, .typing)
    }
}
