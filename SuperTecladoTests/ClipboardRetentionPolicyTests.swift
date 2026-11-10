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

    func testTemporaryClipboardKeepsSeveralCopyEvents() throws {
        let (storage, suite) = try makeStorage()
        defer { storage.fallbackDefaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "primera copia",
                pasteboardChangeCount: 91_001,
                maximumItems: 10,
                storage: storage
            )
        )
        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "segunda copia",
                pasteboardChangeCount: 91_002,
                maximumItems: 10,
                storage: storage
            )
        )
        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "primera copia",
                pasteboardChangeCount: 91_003,
                maximumItems: 10,
                storage: storage
            )
        )

        let clips = SharedClipboardStore.loadTemporaryInbox(storage: storage)
        XCTAssertEqual(clips.count, 3)
        XCTAssertEqual(clips.filter { $0.text == "primera copia" }.count, 2)
    }

    func testSamePasteboardEventIsCapturedOnlyOnce() throws {
        let (storage, suite) = try makeStorage()
        defer { storage.fallbackDefaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(
            SharedClipboardStore.captureTemporaryText(
                "evento único",
                pasteboardChangeCount: 92_001,
                storage: storage
            )
        )
        XCTAssertFalse(
            SharedClipboardStore.captureTemporaryText(
                "evento único",
                pasteboardChangeCount: 92_001,
                storage: storage
            )
        )
        XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox(storage: storage).count, 1)
    }
    private func makeStorage() throws -> (SharedClipboardStore.Storage, String) {
        let suite = "ClipboardRetentionPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (
            .init(directoryURL: nil, fallbackDefaults: defaults, settingsDefaults: defaults),
            suite
        )
    }
}

