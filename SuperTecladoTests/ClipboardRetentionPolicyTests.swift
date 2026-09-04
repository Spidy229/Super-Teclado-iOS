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
}
