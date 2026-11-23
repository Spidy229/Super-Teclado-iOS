import XCTest
@testable import SuperTeclado

final class KeyboardPanelTouchDiagnosticsTests: XCTestCase {
    @MainActor
    func testScrollDeliveryAndStopOutcomeRemainSeparateFromButtonRecognition() async {
        let diagnostics = KeyboardPanelTouchDiagnostics()
        diagnostics.recordScrollTouch(timestamp: 10, isDecelerating: true, isDragging: false, now: 10.025)
        diagnostics.recordStopAttempt(stillDecelerating: true)
        diagnostics.recordScrollTouch(timestamp: 11, isDecelerating: false, isDragging: true, now: 11.010)
        diagnostics.recordButtonTouch(timestamp: 11, now: 11.060)
        diagnostics.recordButtonCancellation()

        XCTAssertEqual(diagnostics.scrollTouches, 2)
        XCTAssertEqual(diagnostics.scrollTouchesDuringDeceleration, 1)
        XCTAssertEqual(diagnostics.scrollTouchesWhileDragging, 1)
        XCTAssertEqual(diagnostics.stopAttempts, 1)
        XCTAssertEqual(diagnostics.stopsStillDecelerating, 1)
        XCTAssertEqual(diagnostics.longestScrollDelivery, 0.025, accuracy: 0.0001)
        XCTAssertEqual(diagnostics.buttonTouches, 1)
        XCTAssertEqual(diagnostics.buttonTaps, 0)
        XCTAssertEqual(diagnostics.buttonCancellations, 1)
        XCTAssertEqual(diagnostics.longestButtonDelivery, 0.060, accuracy: 0.0001)

        diagnostics.recordStopAttempt(stillDecelerating: false)
        diagnostics.recordButtonTouch(timestamp: 12, now: 12.005)
        diagnostics.recordButtonTap()
        XCTAssertEqual(diagnostics.stopAttempts, 2)
        XCTAssertEqual(diagnostics.stopsStillDecelerating, 1)
        XCTAssertEqual(diagnostics.buttonTaps, 1)

        diagnostics.reset()
        XCTAssertEqual(diagnostics.scrollTouches, 0)
        XCTAssertEqual(diagnostics.scrollTouchesDuringDeceleration, 0)
        XCTAssertEqual(diagnostics.scrollTouchesWhileDragging, 0)
        XCTAssertEqual(diagnostics.stopAttempts, 0)
        XCTAssertEqual(diagnostics.stopsStillDecelerating, 0)
        XCTAssertEqual(diagnostics.longestScrollDelivery, 0)
        XCTAssertEqual(diagnostics.buttonTouches, 0)
        XCTAssertEqual(diagnostics.buttonTaps, 0)
        XCTAssertEqual(diagnostics.buttonCancellations, 0)
        XCTAssertEqual(diagnostics.longestButtonDelivery, 0)
    }

    @MainActor
    func testInvalidClockIntervalsDoNotHideLaterRealDeliveryDelay() async {
        let diagnostics = KeyboardPanelTouchDiagnostics()
        diagnostics.recordScrollTouch(timestamp: .nan, isDecelerating: false, isDragging: false, now: 1)
        diagnostics.recordScrollTouch(timestamp: 5, isDecelerating: false, isDragging: false, now: 4)
        diagnostics.recordButtonTouch(timestamp: 0, now: .infinity)
        XCTAssertEqual(diagnostics.longestScrollDelivery, 0)
        XCTAssertEqual(diagnostics.longestButtonDelivery, 0)

        diagnostics.recordScrollTouch(timestamp: 10, isDecelerating: false, isDragging: false, now: 10.2)
        diagnostics.recordButtonTouch(timestamp: 10, now: 10.1)
        XCTAssertEqual(diagnostics.longestScrollDelivery, 0.2, accuracy: 0.0001)
        XCTAssertEqual(diagnostics.longestButtonDelivery, 0.1, accuracy: 0.0001)
    }
}
