import Foundation
import XCTest
@testable import SuperTeclado

final class ClipboardRetentionPolicyTests: XCTestCase {
    func testExpirationDateAddsConfiguredHours() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let expiration = try XCTUnwrap(
            ClipboardRetentionPolicy.expirationDate(
                hours: 24,
                from: start,
                calendar: Calendar(identifier: .gregorian)
            )
        )

        XCTAssertEqual(expiration.timeIntervalSince(start), 86_400, accuracy: 0.001)
    }

    func testTemporaryItemExpiresAtBoundary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(
            ClipboardRetentionPolicy.isExpired(
                isTemporary: true,
                expiresAt: now,
                at: now
            )
        )
    }

    func testPermanentOrUndatedItemNeverExpiresAsTemporary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertFalse(
            ClipboardRetentionPolicy.isExpired(
                isTemporary: false,
                expiresAt: now.addingTimeInterval(-1),
                at: now
            )
        )
        XCTAssertFalse(
            ClipboardRetentionPolicy.isExpired(
                isTemporary: true,
                expiresAt: nil,
                at: now
            )
        )
    }

    func testPromotionClearsTemporaryExpiration() {
        let item = ClipboardItem(
            text: "Ejemplo",
            kind: .text,
            contentHash: "hash",
            isTemporary: true,
            expiresAt: .now
        )

        item.promoteToPermanent()

        XCTAssertTrue(item.isPermanent)
        XCTAssertNil(item.expiresAt)
    }

    func testTemporaryClipboardKeepsSeveralCopyEvents() {
        SharedClipboardStore.clearTemporaryInbox()
        defer { SharedClipboardStore.clearTemporaryInbox() }

        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "primera copia",
                pasteboardChangeCount: 91_001,
                maximumItems: 10
            )
        )
        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "segunda copia",
                pasteboardChangeCount: 91_002,
                maximumItems: 10
            )
        )
        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "primera copia",
                pasteboardChangeCount: 91_003,
                maximumItems: 10
            )
        )

        let clips = SharedClipboardStore.loadTemporaryInbox()
        XCTAssertEqual(clips.count, 3)
        XCTAssertEqual(clips.filter { $0.text == "primera copia" }.count, 2)
    }

    func testSamePasteboardEventIsCapturedOnlyOnce() {
        SharedClipboardStore.clearTemporaryInbox()
        defer { SharedClipboardStore.clearTemporaryInbox() }

        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "evento único",
                pasteboardChangeCount: 92_001
            )
        )
        XCTAssertFalse(
            SharedClipboardStore.captureTemporaryText(
                "evento único",
                pasteboardChangeCount: 92_001
            )
        )
        XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox().count, 1)
    }
}

