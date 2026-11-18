import UIKit
import XCTest

final class KeyGridDeliveryTests: XCTestCase {
    @MainActor
    private final class Finger: UITouch {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
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
    func testGridUsesNativeHitTestingAndPreservesHostGestureConfiguration() async {
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
        XCTAssertTrue(grid.gestureRecognizers?.isEmpty ?? true)
        XCTAssertTrue(gate.delaysTouchesBegan)
        XCTAssertTrue(gate.delaysTouchesEnded)
        for point in [CGPoint(x: 2, y: 42), CGPoint(x: 195, y: 162), CGPoint(x: 388, y: 248)] {
            XCTAssertTrue(window.hitTest(point, with: nil) === grid)
        }
        XCTAssertFalse(window.hitTest(CGPoint(x: 20, y: 20), with: nil) === grid)
        grid.isHidden = true
        XCTAssertFalse(window.hitTest(CGPoint(x: 195, y: 162), with: nil) === grid)
    }
}
