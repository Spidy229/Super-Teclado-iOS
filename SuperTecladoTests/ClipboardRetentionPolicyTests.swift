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

    func testCopyingSameTextAgainMovesItToTheTop() {
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
        XCTAssertEqual(clips.map(\.text), ["primera copia", "segunda copia"])
    }

    func testTemporaryInboxRespectsLimit() {
        SharedClipboardStore.clearTemporaryInbox()
        defer { SharedClipboardStore.clearTemporaryInbox() }

        for index in 0..<5 {
            SharedClipboardStore.captureTemporaryText(
                "copia \(index)",
                pasteboardChangeCount: 93_000 + index,
                maximumItems: 3
            )
        }

        XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox().count, 3)
    }

    func testKeyboardDeletionIsRecordedForTheApp() throws {
        SharedClipboardStore.clearTemporaryInbox()
        _ = SharedClipboardStore.consumeDeletedIDs()
        defer {
            SharedClipboardStore.clearTemporaryInbox()
            _ = SharedClipboardStore.consumeDeletedIDs()
        }

        SharedClipboardStore.captureTemporaryText("borrar", pasteboardChangeCount: 94_001)
        let clip = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox().first)

        SharedClipboardStore.deleteTemporary(ids: [clip.id])

        XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox().isEmpty)
        XCTAssertEqual(SharedClipboardStore.consumeDeletedIDs(), [clip.id])
        XCTAssertTrue(SharedClipboardStore.pendingDeletedIDs().isEmpty)
    }

    func testPinAndUnpinMovesClipBetweenSections() throws {
        let originalSaved = SharedClipboardStore.load()
        SharedClipboardStore.clearTemporaryInbox()
        defer {
            SharedClipboardStore.save(originalSaved)
            SharedClipboardStore.clearTemporaryInbox()
            _ = SharedClipboardStore.consumeDeletedIDs()
        }

        SharedClipboardStore.captureTemporaryText("fijar esto", pasteboardChangeCount: 95_001)
        let temporary = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox().first)

        XCTAssertTrue(SharedClipboardStore.promoteTemporary(id: temporary.id))
        XCTAssertTrue(SharedClipboardStore.load().contains { $0.id == temporary.id && $0.isPinned })
        XCTAssertFalse(SharedClipboardStore.loadTemporaryInbox().contains { $0.id == temporary.id })

        XCTAssertTrue(SharedClipboardStore.demoteSaved(id: temporary.id))
        XCTAssertFalse(SharedClipboardStore.load().contains { $0.id == temporary.id })
        XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox().first?.text, "fijar esto")
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

