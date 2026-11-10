import XCTest
@testable import SuperTeclado

final class KeyboardClipValidityTests: XCTestCase {
    func testTemporarySnapshotPreservesExpiryAndRejectsExactBoundary() {
        let expiry = Date(timeIntervalSince1970: 1_700_000_120)
        let clip = KeyboardClip(recent: SharedTemporaryClip(
            id: UUID(),
            text: "contenido privado",
            capturedAt: expiry.addingTimeInterval(-120),
            kindRawValue: "text",
            expiresAt: expiry,
            isSensitive: true
        ))

        XCTAssertEqual(clip.expiresAt, expiry)
        XCTAssertTrue(clip.isSensitive)
        XCTAssertFalse(clip.isExpired(at: expiry.addingTimeInterval(-0.001)))
        XCTAssertTrue(clip.isExpired(at: expiry))
        XCTAssertTrue(clip.isExpired(at: expiry.addingTimeInterval(60)))
    }

    func testImageSnapshotAlsoExpires() {
        let expiry = Date(timeIntervalSince1970: 1_700_000_120)
        let clip = KeyboardClip(recent: SharedTemporaryClip(
            id: UUID(),
            text: "",
            capturedAt: expiry.addingTimeInterval(-120),
            kindRawValue: "image",
            expiresAt: expiry,
            imageFileName: "test-image.jpg"
        ))

        XCTAssertTrue(clip.isImage)
        XCTAssertTrue(clip.isExpired(at: expiry))
    }

    func testPinnedAndUndatedSnapshotsRemainAvailable() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = KeyboardClip(saved: SharedClipboardClip(
            id: UUID(),
            text: "fijado",
            createdAt: date,
            updatedAt: date,
            kindRawValue: "text",
            isFavorite: false,
            isPinned: true
        ))
        let undated = KeyboardClip(recent: SharedTemporaryClip(
            id: UUID(),
            text: "sin fecha",
            capturedAt: date,
            kindRawValue: "text",
            expiresAt: nil
        ))

        XCTAssertTrue(saved.isSaved)
        XCTAssertFalse(saved.isExpired(at: date.addingTimeInterval(86_400)))
        XCTAssertFalse(undated.isExpired(at: date.addingTimeInterval(86_400)))
    }
}
