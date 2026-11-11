import UIKit

/// Contadores locales del panel: no publican cambios, guardan texto ni intervienen en gestos.
@MainActor
final class KeyboardPanelTouchDiagnostics {
    static let shared = KeyboardPanelTouchDiagnostics()

    private(set) var scrollTouches = 0
    private(set) var scrollTouchesDuringDeceleration = 0
    private(set) var scrollTouchesWhileDragging = 0
    private(set) var stopAttempts = 0
    private(set) var stopsStillDecelerating = 0
    private(set) var longestScrollDelivery: TimeInterval = 0
    private(set) var buttonTouches = 0
    private(set) var buttonTaps = 0
    private(set) var buttonCancellations = 0
    private(set) var longestButtonDelivery: TimeInterval = 0

    func recordScrollTouch(timestamp: TimeInterval, isDecelerating: Bool, isDragging: Bool, now: TimeInterval) {
        scrollTouches += 1
        if isDecelerating { scrollTouchesDuringDeceleration += 1 }
        if isDragging { scrollTouchesWhileDragging += 1 }
        longestScrollDelivery = max(longestScrollDelivery, delivery(timestamp: timestamp, now: now))
    }

    /// Es el estado inmediatamente después de pedir el frenado, no una animación observada.
    func recordStopAttempt(stillDecelerating: Bool) {
        stopAttempts += 1
        if stillDecelerating { stopsStillDecelerating += 1 }
    }

    func recordButtonTouch(timestamp: TimeInterval, now: TimeInterval) {
        buttonTouches += 1
        longestButtonDelivery = max(longestButtonDelivery, delivery(timestamp: timestamp, now: now))
    }

    func recordButtonTap() { buttonTaps += 1 }
    func recordButtonCancellation() { buttonCancellations += 1 }

    func reset() {
        scrollTouches = 0
        scrollTouchesDuringDeceleration = 0
        scrollTouchesWhileDragging = 0
        stopAttempts = 0
        stopsStillDecelerating = 0
        longestScrollDelivery = 0
        buttonTouches = 0
        buttonTaps = 0
        buttonCancellations = 0
        longestButtonDelivery = 0
    }

    var report: String {
        [
            String(format: "Ajustes · scroll: %d toques recibidos (%d durante inercia, %d durante arrastre) · retraso máximo %.0f ms", scrollTouches, scrollTouchesDuringDeceleration, scrollTouchesWhileDragging, longestScrollDelivery * 1000),
            "Ajustes · intentos de frenar: \(stopAttempts) (aún con inercia inmediatamente después: \(stopsStillDecelerating))",
            String(format: "Ajustes · botones: %d comienzos, %d toques reconocidos, %d cancelaciones de iOS · retraso máximo %.0f ms", buttonTouches, buttonTaps, buttonCancellations, longestButtonDelivery * 1000)
        ].joined(separator: "\n")
    }

    private func delivery(timestamp: TimeInterval, now: TimeInterval) -> TimeInterval {
        let interval = now - timestamp
        return interval.isFinite ? max(0, interval) : 0
    }
}
