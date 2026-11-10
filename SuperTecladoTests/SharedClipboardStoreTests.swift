import Foundation
import XCTest
@testable import SuperTeclado

final class SharedClipboardStoreTests: XCTestCase {
    func testDeletedSharedHistoryCannotReturnFromAnotherProcessesFallback() throws {
        try withStorage { storage in
            let clip = savedClip("private copy")
            storage.fallbackDefaults.set(
                try JSONEncoder().encode([clip]), forKey: "super-teclado-saved-fallback"
            )
            XCTAssertTrue(SharedClipboardStore.save([], storage: storage))
            // Simulate an older extension process still holding its own stale fallback.
            storage.fallbackDefaults.set(
                try JSONEncoder().encode([clip]), forKey: "super-teclado-saved-fallback"
            )

            XCTAssertTrue(SharedClipboardStore.load(storage: storage).isEmpty)
            XCTAssertNil(storage.fallbackDefaults.data(forKey: "super-teclado-saved-fallback"))
            SharedClipboardStore.markUsed(id: clip.id, storage: storage)
            XCTAssertTrue(SharedClipboardStore.load(storage: storage).isEmpty)
        }
    }

    func testClearedSharedInboxCannotReturnFromStaleTemporaryFallback() throws {
        try withStorage { storage in
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                "temporary", pasteboardChangeCount: 10, storage: storage
            ))
            let stale = SharedClipboardStore.loadTemporaryInbox(storage: storage)
            XCTAssertTrue(SharedClipboardStore.clearTemporaryInbox(storage: storage))
            storage.fallbackDefaults.set(
                try JSONEncoder().encode(stale), forKey: "super-teclado-temporary-fallback"
            )

            XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox(storage: storage).isEmpty)
            XCTAssertFalse(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 10, storage: storage))
        }
    }

    func testCapturePreservesWhitespaceAndOnlyRejectsWhitespaceOnlyContent() throws {
        try withStorage { storage in
            let source = "  first line\n\tsecond line\n"
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                source, pasteboardChangeCount: 20, storage: storage
            ))
            XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox(storage: storage).first?.text, source)
            XCTAssertFalse(SharedClipboardStore.captureTemporaryText(
                " \n\t", pasteboardChangeCount: 21, storage: storage
            ))
            XCTAssertTrue(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 21, storage: storage))
        }
    }

    func testPromotionDoesNotRecaptureTheSamePasteboardEvent() throws {
        try withStorage { storage in
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                "save this", pasteboardChangeCount: 30, storage: storage
            ))
            let clip = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox(storage: storage).first)
            XCTAssertTrue(SharedClipboardStore.promoteTemporary(id: clip.id, storage: storage))
            XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox(storage: storage).isEmpty)
            XCTAssertFalse(SharedClipboardStore.captureTemporaryText(
                "save this", pasteboardChangeCount: 30, storage: storage
            ))
            // A new copy of the same text remains a separate event.
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                "save this", pasteboardChangeCount: 31, storage: storage
            ))
        }
    }

    func testExpiredAndReplacedInboxKeepsTheLastCaptureEvent() throws {
        try withStorage { storage in
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                "expires", pasteboardChangeCount: 40, storage: storage
            ))
            var expired = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox(storage: storage).first)
            expired.expiresAt = .distantPast
            XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox([expired], storage: storage))
            XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox(storage: storage).isEmpty)
            XCTAssertFalse(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 40, storage: storage))
            XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox([], storage: storage))
            XCTAssertFalse(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 40, storage: storage))
        }
    }

    func testLegacyTemporaryArrayMigratesAndKeepsCaptureMarkerWhenCleared() throws {
        try withStorage { storage in
            let clip = SharedTemporaryClip(
                id: UUID(), text: "legacy", capturedAt: .now, kindRawValue: "text",
                expiresAt: .distantFuture, pasteboardChangeCount: 50
            )
            let directory = try XCTUnwrap(storage.directoryURL)
            try JSONEncoder().encode([clip]).write(
                to: directory.appendingPathComponent("super-teclado-temporary-inbox.json")
            )
            XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox(storage: storage).map(\.id), [clip.id])
            XCTAssertTrue(SharedClipboardStore.clearTemporaryInbox(storage: storage))
            XCTAssertFalse(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 50, storage: storage))
        }
    }

    func testFallbackIsAvailableOnlyWithoutGroupContainer() throws {
        try withStorage { storage in
            let fallback = SharedClipboardStore.Storage(
                directoryURL: nil,
                fallbackDefaults: storage.fallbackDefaults,
                settingsDefaults: storage.settingsDefaults
            )
            let clip = savedClip("local fallback")
            XCTAssertTrue(SharedClipboardStore.save([clip], storage: fallback))
            XCTAssertEqual(SharedClipboardStore.load(storage: fallback).map(\.id), [clip.id])
            // A missing shared file is authoritative too, rather than importing stale defaults.
            XCTAssertTrue(SharedClipboardStore.load(storage: storage).isEmpty)
        }
    }

    func testCorruptSharedInboxDoesNotFallBackOrGetOverwrittenByCapture() throws {
        try withStorage { storage in
            let directory = try XCTUnwrap(storage.directoryURL)
            let url = directory.appendingPathComponent("super-teclado-temporary-inbox.json")
            let invalid = Data("not valid JSON".utf8)
            try invalid.write(to: url)
            let stale = SharedTemporaryClip(
                id: UUID(), text: "stale", capturedAt: .now, kindRawValue: "text",
                expiresAt: .distantFuture, pasteboardChangeCount: 60
            )
            storage.fallbackDefaults.set(
                try JSONEncoder().encode([stale]), forKey: "super-teclado-temporary-fallback"
            )

            XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox(storage: storage).isEmpty)
            XCTAssertFalse(SharedClipboardStore.canRead(storage: storage))
            XCTAssertFalse(SharedClipboardStore.captureTemporaryText(
                "new text", pasteboardChangeCount: 61, storage: storage
            ))
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    func testMainAppEventSurvivesPublicationAndIsNotReplacedByAnOlderClip() throws {
        try withStorage { storage in
            XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox(
                [], lastPasteboardChangeCount: 70, storage: storage
            ))
            let older = SharedTemporaryClip(
                id: UUID(), text: "older", capturedAt: .now, kindRawValue: "text",
                expiresAt: .distantFuture, pasteboardChangeCount: 69
            )
            XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox([older], storage: storage))
            XCTAssertFalse(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 70, storage: storage))
            XCTAssertTrue(SharedClipboardStore.clearTemporaryInbox(storage: storage))
            XCTAssertFalse(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 70, storage: storage))
        }
    }

    func testCounterFromPreviousBootDoesNotSuppressANewCopy() throws {
        try withStorage { storage in
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                "before reboot", pasteboardChangeCount: 80, storage: storage
            ))
            let directory = try XCTUnwrap(storage.directoryURL)
            let url = directory.appendingPathComponent("super-teclado-temporary-inbox.json")
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var event = try XCTUnwrap(document["lastPasteboardEvent"] as? [String: Any])
            event["bootSession"] = "a previous device boot"
            document["lastPasteboardEvent"] = event
            try JSONSerialization.data(withJSONObject: document).write(to: url)

            XCTAssertTrue(SharedClipboardStore.shouldCapture(pasteboardChangeCount: 80, storage: storage))
        }
    }

    private func savedClip(_ text: String) -> SharedClipboardClip {
        SharedClipboardClip(
            id: UUID(), text: text, createdAt: .now, updatedAt: .now,
            kindRawValue: "text", isFavorite: false, isPinned: false
        )
    }

    private func withStorage(
        _ body: (SharedClipboardStore.Storage) throws -> Void
    ) throws {
        let suite = "SharedClipboardStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(SharedClipboardStore.Storage(
            directoryURL: directory, fallbackDefaults: defaults, settingsDefaults: defaults
        ))
    }
}
