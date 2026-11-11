import UIKit
import XCTest
@testable import SuperTeclado

/// Pruebas de geometría y configuración pública de UIKit. La entrega de toques físicos
/// durante la inercia de SwiftUI necesita además una prueba en el dispositivo.
final class KeyboardScrollTouchPolicyTests: XCTestCase {
    @MainActor
    func testScrollingContentDoesNotTurnStationaryFingerIntoDrag() async {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let scroll = UIScrollView(frame: root.bounds)
        let button = UIView(frame: CGRect(x: 20, y: 300, width: 100, height: 40))
        scroll.contentSize = CGSize(width: 320, height: 1_200)
        root.addSubview(scroll)
        scroll.addSubview(button)

        let reference = KeyboardScrollTouchPolicy.referenceView(for: button)
        XCTAssertTrue(reference === root)
        let stationaryPoint = CGPoint(x: 50, y: 350)
        let localStart = button.convert(stationaryPoint, from: reference)
        let start = button.convert(localStart, to: reference)
        scroll.contentOffset.y = 80
        let localEnd = button.convert(stationaryPoint, from: reference)
        let end = button.convert(localEnd, to: reference)

        XCTAssertNotEqual(localStart, localEnd)
        XCTAssertFalse(KeyboardScrollTouchPolicy.movedBeyondTap(from: start, to: end))
        XCTAssertTrue(KeyboardScrollTouchPolicy.movedBeyondTap(from: start, to: CGPoint(x: end.x, y: end.y + 13)))
    }

    @MainActor
    func testTapSlopIncludesFinalFingerPosition() async {
        XCTAssertFalse(KeyboardScrollTouchPolicy.movedBeyondTap(from: .zero, to: CGPoint(x: 12, y: 0)))
        XCTAssertTrue(KeyboardScrollTouchPolicy.movedBeyondTap(from: .zero, to: CGPoint(x: 9, y: 9)))
    }

    @MainActor
    func testOnlyContainingScrollPansQualifyForCoexistence() async {
        let outer = UIScrollView()
        let inner = UIScrollView()
        let unrelated = UIScrollView()
        let button = UIView()
        outer.addSubview(inner)
        inner.addSubview(button)

        XCTAssertTrue(KeyboardScrollTouchPolicy.isAncestorScrollPan(outer.panGestureRecognizer, of: button))
        XCTAssertTrue(KeyboardScrollTouchPolicy.isAncestorScrollPan(inner.panGestureRecognizer, of: button))
        XCTAssertFalse(KeyboardScrollTouchPolicy.isAncestorScrollPan(unrelated.panGestureRecognizer, of: button))
        XCTAssertFalse(KeyboardScrollTouchPolicy.isAncestorScrollPan(UITapGestureRecognizer(), of: button))
    }

    @MainActor
    func testScopeRestoresDelayAndLeavesExistingRecognizersUntouched() async throws {
        let scroll = UIScrollView()
        scroll.delaysContentTouches = true
        let pan = scroll.panGestureRecognizer
        let panDelay = pan.delaysTouchesBegan
        let original = recognizers(in: scroll)
        let scope = KeyboardScrollTouchScope()
        scope.attach(to: scroll)
        scope.attach(to: scroll)

        XCTAssertFalse(scroll.delaysContentTouches)
        XCTAssertTrue(pan.isEnabled)
        XCTAssertEqual(pan.delaysTouchesBegan, panDelay)
        let observer = try XCTUnwrap(scroll.gestureRecognizers?.first { !original.contains(ObjectIdentifier($0)) })
        XCTAssertFalse(observer.cancelsTouchesInView)
        XCTAssertFalse(observer.delaysTouchesBegan)
        XCTAssertFalse(observer.delaysTouchesEnded)
        XCTAssertFalse(observer.canPrevent(pan))
        XCTAssertFalse(observer.canBePrevented(by: pan))

        scope.detach()
        scope.detach()
        XCTAssertTrue(scroll.delaysContentTouches)
        XCTAssertEqual(recognizers(in: scroll), original)
    }

    @MainActor
    func testOverlappingScopesRestoreOnlyAfterLastOwnerLeaves() async {
        let scroll = UIScrollView()
        scroll.delaysContentTouches = true
        let original = recognizers(in: scroll)
        let first = KeyboardScrollTouchScope()
        let second = KeyboardScrollTouchScope()
        first.attach(to: scroll)
        second.attach(to: scroll)
        XCTAssertEqual(recognizers(in: scroll).count, original.count + 1)

        first.detach()
        XCTAssertFalse(scroll.delaysContentTouches)
        second.detach()
        XCTAssertTrue(scroll.delaysContentTouches)
        XCTAssertEqual(recognizers(in: scroll), original)
    }

    @MainActor
    func testMovingScopeRestoresEachScrollsOriginalDelay() async {
        let first = UIScrollView()
        let second = UIScrollView()
        first.delaysContentTouches = false
        second.delaysContentTouches = true
        let original = recognizers(in: first)
        let scope = KeyboardScrollTouchScope()
        scope.attach(to: first)
        scope.attach(to: second)

        XCTAssertFalse(first.delaysContentTouches)
        XCTAssertEqual(recognizers(in: first), original)
        XCTAssertFalse(second.delaysContentTouches)
        scope.detach()
        XCTAssertTrue(second.delaysContentTouches)
    }

    @MainActor
    func testStopInertiaUsesCurrentOffsetAndDoesNotInterruptActiveDrag() async {
        let scroll = ReportedMotionScrollView()
        scroll.contentOffset = CGPoint(x: 4, y: 120)
        scroll.calls = []
        KeyboardScrollTouchPolicy.stopDecelerationIfNeeded(in: scroll)
        XCTAssertTrue(scroll.calls.isEmpty)

        scroll.reportsDecelerating = true
        scroll.reportsDragging = true
        KeyboardScrollTouchPolicy.stopDecelerationIfNeeded(in: scroll)
        XCTAssertTrue(scroll.calls.isEmpty)

        scroll.reportsDragging = false
        KeyboardScrollTouchPolicy.stopDecelerationIfNeeded(in: scroll)
        XCTAssertEqual(scroll.calls.count, 1)
        XCTAssertEqual(scroll.calls.first?.offset, CGPoint(x: 4, y: 120))
        XCTAssertEqual(scroll.calls.first?.animated, false)
    }

    @MainActor
    private func recognizers(in scroll: UIScrollView) -> Set<ObjectIdentifier> {
        Set((scroll.gestureRecognizers ?? []).map(ObjectIdentifier.init))
    }
}

@MainActor
private final class ReportedMotionScrollView: UIScrollView {
    var reportsDecelerating = false
    var reportsDragging = false
    var calls: [(offset: CGPoint, animated: Bool)] = []

    override var isDecelerating: Bool { reportsDecelerating }
    override var isDragging: Bool { reportsDragging }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        calls.append((contentOffset, animated))
        super.setContentOffset(contentOffset, animated: animated)
    }
}
