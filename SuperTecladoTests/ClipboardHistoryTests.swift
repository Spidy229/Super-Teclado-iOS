import XCTest
@testable import SuperTeclado

final class ClipboardHistoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SharedClipboardStore.clearTemporaryInbox()
        _ = SharedClipboardStore.consumeDeletedIDs()
    }

    override func tearDown() {
        SharedClipboardStore.clearTemporaryInbox()
        _ = SharedClipboardStore.consumeDeletedIDs()
        super.tearDown()
    }

    func testSensitiveDetection() {
        XCTAssertTrue(ClipboardClassifier.isCardNumber("4111 1111 1111 1111"))
        XCTAssertFalse(ClipboardClassifier.isCardNumber("4111 1111 1111 1112"))
        XCTAssertTrue(ClipboardClassifier.isIBAN("ES91 2100 0418 4502 0005 1332"))
        XCTAssertTrue(ClipboardClassifier.looksLikePassword("Xk9#mPq2!vLz"))
        XCTAssertFalse(ClipboardClassifier.looksLikePassword("SharedClipboardStore.swift"))
        XCTAssertFalse(ClipboardClassifier.isSensitive("Nos vemos a las 5"))
    }

    func testLinkAndColorDetails() {
        XCTAssertEqual(ClipboardClassifier.linkDomain("https://www.google.com/search?q=1"), "google.com")
        XCTAssertNil(ClipboardClassifier.linkDomain("hola"))
        XCTAssertNotNil(ClipboardClassifier.hexColor("#FF8000"))
        XCTAssertNil(ClipboardClassifier.hexColor("#FF80"))
    }

    func testPasteAsTransforms() {
        XCTAssertEqual(ClipboardClassifier.Transform.singleLine.apply(to: "uno\n  dos \n\ntres"), "uno dos tres")
        XCTAssertEqual(ClipboardClassifier.Transform.trimmed.apply(to: "  uno   dos \n tres  "), "uno dos\ntres")
        XCTAssertEqual(ClipboardClassifier.Transform.uppercase.apply(to: "hola"), "HOLA")
    }

    func testSensitiveClipsAreMarkedAndExpireSoon() throws {
        XCTAssertTrue(SharedClipboardStore.captureTemporaryText("secreto", pasteboardChangeCount: nil, isSensitive: true))
        let clip = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox().first)
        XCTAssertEqual(clip.isSensitive, true)
        let expiresAt = try XCTUnwrap(clip.expiresAt)
        XCTAssertLessThanOrEqual(expiresAt.timeIntervalSinceNow, ClipboardClassifier.sensitiveLifetime + 1)
    }

    func testCapturesWithoutChangeCountAreNotDeduplicatedByIt() {
        XCTAssertTrue(SharedClipboardStore.captureTemporaryText("uno", pasteboardChangeCount: nil))
        XCTAssertTrue(SharedClipboardStore.captureTemporaryText("dos", pasteboardChangeCount: nil))
        XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox().count, 2)
    }

    func testDeletionCanBeUndone() throws {
        SharedClipboardStore.captureTemporaryText("deshacer", pasteboardChangeCount: 96_001)
        let clip = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox().first)

        let removed = SharedClipboardStore.deleteTemporary(ids: [clip.id], removeImages: false)
        XCTAssertEqual(removed.map(\.id), [clip.id])
        XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox().isEmpty)
        XCTAssertTrue(SharedClipboardStore.pendingDeletedIDs().contains(clip.id))

        SharedClipboardStore.restore(saved: [], temporary: removed)
        XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox().map(\.id), [clip.id])
        XCTAssertFalse(SharedClipboardStore.pendingDeletedIDs().contains(clip.id))
    }

    func testFolderCanBeAssignedToSavedClip() throws {
        let originalSaved = SharedClipboardStore.load()
        defer { SharedClipboardStore.save(originalSaved) }

        SharedClipboardStore.captureTemporaryText("para carpeta", pasteboardChangeCount: 97_001)
        let clip = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox().first)
        SharedClipboardStore.promoteTemporary(id: clip.id)
        SharedClipboardStore.setFolder("Trabajo", forSavedID: clip.id)

        XCTAssertEqual(SharedClipboardStore.load().first { $0.id == clip.id }?.folderName, "Trabajo")
    }

    func testPrivateMarkersFromPasswordManagers() {
        XCTAssertTrue(ClipboardCapture.isPrivate(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardCapture.isPrivate(types: ["public.utf8-plain-text"]))
    }
}
