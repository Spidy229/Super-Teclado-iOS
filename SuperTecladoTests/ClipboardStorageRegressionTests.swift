import Foundation
import SwiftData
import XCTest
@testable import SuperTeclado

final class ClipboardStorageRegressionTests: XCTestCase {
    @MainActor
    func testSensitiveClipRemainsMaskedWhenPinnedAndExpiresSoonWhenUnpinned() async throws {
        try withStorage { storage in
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                "secret", pasteboardChangeCount: nil, isSensitive: true, storage: storage
            ))
            let recent = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox(storage: storage).first)
            XCTAssertTrue(SharedClipboardStore.promoteTemporary(id: recent.id, storage: storage))
            XCTAssertEqual(SharedClipboardStore.load(storage: storage).first?.isSensitive, true)
            XCTAssertTrue(SharedClipboardStore.demoteSaved(id: recent.id, storage: storage))
            let unpinned = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox(storage: storage).first)
            XCTAssertEqual(unpinned.isSensitive, true)
            XCTAssertLessThanOrEqual(try XCTUnwrap(unpinned.expiresAt).timeIntervalSinceNow,
                                     ClipboardClassifier.sensitiveLifetime + 1)
        }
    }

    @MainActor
    func testCapturedTextPreservesSpacesIndentationAndFinalNewline() async throws {
        try withStorage { storage in
            let text = "  first\n\tsecond\n"
            XCTAssertTrue(SharedClipboardStore.captureTemporaryText(
                text, pasteboardChangeCount: nil, storage: storage
            ))
            XCTAssertEqual(SharedClipboardStore.loadTemporaryInbox(storage: storage).first?.text, text)
        }
    }

    @MainActor
    func testImagesWorkInThePrivateContainerWithoutAppGroup() async throws {
        try withStorage(hasAppGroup: false) { storage in
            let data = Data([0xFF, 0xD8, 1, 2, 0xFF, 0xD9])
            XCTAssertTrue(SharedClipboardStore.captureTemporaryImage(
                data, hash: "image", pasteboardChangeCount: nil, storage: storage
            ))
            let recent = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox(storage: storage).first)
            let fileName = try XCTUnwrap(recent.imageFileName)
            XCTAssertEqual(SharedClipboardStore.imageData(fileName: fileName, storage: storage), data)
            XCTAssertTrue(SharedClipboardStore.promoteTemporary(id: recent.id, storage: storage))
            XCTAssertEqual(SharedClipboardStore.load(storage: storage).first?.imageFileName, fileName)
            let context = try memoryContext()
            XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: storage))
            XCTAssertEqual(try context.fetch(FetchDescriptor<ClipboardItem>()).first?.imageData, data)
        }
    }

    @MainActor
    func testImagePathsCannotEscapeTheImageDirectory() async throws {
        try withStorage { storage in
            XCTAssertNil(SharedClipboardStore.imageURL(fileName: "../private.json", storage: storage))
            XCTAssertNil(SharedClipboardStore.imageURL(fileName: "/private.json", storage: storage))
            XCTAssertNil(SharedClipboardStore.imageURL(fileName: "..\\private.json", storage: storage))
        }
    }

    @MainActor
    func testSharedFileDoesNotRestoreStaleFallbackWhenMissingOrCorrupt() async throws {
        try withStorage { storage in
            let stale = savedClip("deleted")
            storage.defaults.set(try JSONEncoder().encode([stale]), forKey: "super-teclado-saved-fallback")
            XCTAssertTrue(SharedClipboardStore.load(storage: storage).isEmpty)
            let url = try XCTUnwrap(storage.directoryURL).appendingPathComponent("super-teclado-history.json")
            try Data("invalid JSON".utf8).write(to: url)
            XCTAssertTrue(SharedClipboardStore.load(storage: storage).isEmpty)
            XCTAssertFalse(SharedClipboardStore.canRead(storage: storage))
            XCTAssertFalse(KeyboardHistorySync.synchronize(with: try memoryContext(), storage: storage))
            XCTAssertEqual(try Data(contentsOf: url), Data("invalid JSON".utf8))
        }
    }

    @MainActor
    func testSyncPreservesUnlimitedRetentionCaptureIdentityAndSensitivity() async throws {
        try withStorage { storage in
            let recent = SharedTemporaryClip(
                id: UUID(), text: "masked", capturedAt: .now, kindRawValue: "text",
                expiresAt: nil, pasteboardChangeCount: 123, isSensitive: true
            )
            XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox([recent], storage: storage))
            let context = try memoryContext()
            XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: storage))
            let item = try XCTUnwrap(context.fetch(FetchDescriptor<ClipboardItem>()).first)
            XCTAssertNil(item.expiresAt)
            XCTAssertTrue(item.isSensitive)
            let published = try XCTUnwrap(SharedClipboardStore.loadTemporaryInbox(storage: storage).first)
            XCTAssertNil(published.expiresAt)
            XCTAssertEqual(published.pasteboardChangeCount, 123)
        }
    }

    @MainActor
    func testSyncDoesNotAcknowledgeDeletionWhenImagePublicationFails() async throws {
        try withStorage { storage in
            let deleted = savedClip("deleted in keyboard")
            XCTAssertTrue(SharedClipboardStore.save([deleted], storage: storage))
            SharedClipboardStore.recordDeletion(of: [deleted.id], storage: storage)
            let directory = try XCTUnwrap(storage.directoryURL)
            // A file in place of the image directory makes publication fail predictably.
            try Data([0]).write(to: directory.appendingPathComponent("super-teclado-images"))
            let context = try memoryContext()
            context.insert(ClipboardItem(imageData: Data([1, 2]), kind: .image, contentHash: "image"))
            try context.save()

            XCTAssertFalse(KeyboardHistorySync.synchronize(with: context, storage: storage))
            XCTAssertTrue(SharedClipboardStore.pendingDeletedIDs(storage: storage).contains(deleted.id))
            XCTAssertEqual(SharedClipboardStore.load(storage: storage).map(\.id), [deleted.id])
            try FileManager.default.removeItem(at: directory.appendingPathComponent("super-teclado-images"))
            XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: storage))
            XCTAssertTrue(SharedClipboardStore.pendingDeletedIDs(storage: storage).isEmpty)
            XCTAssertFalse(SharedClipboardStore.load(storage: storage).contains { $0.id == deleted.id })
        }
    }

    @MainActor
    private func memoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: ClipboardItem.self, configurations: configuration))
    }

    private func savedClip(_ text: String) -> SharedClipboardClip {
        SharedClipboardClip(id: UUID(), text: text, createdAt: .now, updatedAt: .now,
                            kindRawValue: "text", isFavorite: false, isPinned: true)
    }

    private func withStorage(
        hasAppGroup: Bool = true,
        _ body: (SharedClipboardStore.Storage) throws -> Void
    ) throws {
        let name = "ClipboardStorageRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(SharedClipboardStore.Storage(
            directoryURL: hasAppGroup ? directory : nil, localDirectoryURL: directory,
            defaults: defaults, settingsDefaults: defaults
        ))
    }
}
