import Foundation
import SwiftData
import XCTest
@testable import SuperTeclado

final class KeyboardHistorySyncTests: XCTestCase {
    @MainActor
    func testSyncKeepsEveryCopyEventAndItsExpiration() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let captured = Date.now.addingTimeInterval(-60)
        let clips = [
            makeClip(text: "A", captured: captured, hours: 1, event: 101),
            makeClip(text: "B", captured: captured.addingTimeInterval(1), hours: 6, event: 102),
            makeClip(text: "A", captured: captured.addingTimeInterval(2), hours: 168, event: 103)
        ]
        XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox(clips, storage: fixture.storage))
        let container = try makeContainer()
        let context = ModelContext(container)

        XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: fixture.storage))
        XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: fixture.storage))

        let imported = try context.fetch(FetchDescriptor<ClipboardItem>())
        XCTAssertEqual(Set(imported.map(\.id)), Set(clips.map(\.id)))
        XCTAssertEqual(imported.filter { $0.text == "A" }.count, 2)
        for clip in clips {
            let item = try XCTUnwrap(imported.first { $0.id == clip.id })
            XCTAssertTrue(item.isTemporary)
            XCTAssertEqual(item.expiresAt, clip.expiresAt)
            XCTAssertEqual(item.pasteboardChangeCount, clip.pasteboardChangeCount)
        }
        let published = SharedClipboardStore.loadTemporaryInbox(storage: fixture.storage)
        XCTAssertEqual(Set(published.map(\.id)), Set(clips.map(\.id)))
        for clip in clips {
            let result = try XCTUnwrap(published.first { $0.id == clip.id })
            XCTAssertEqual(result.expiresAt, clip.expiresAt)
            XCTAssertEqual(result.pasteboardChangeCount, clip.pasteboardChangeCount)
        }
    }

    @MainActor
    func testPromotingOneCopyDoesNotPromoteAnotherCopyOfTheSameText() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let first = makeClip(text: "Repeated", captured: .now, hours: 1, event: 201)
        let second = makeClip(text: "Repeated", captured: .now, hours: 6, event: 202)
        XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox([first, second], storage: fixture.storage))
        XCTAssertTrue(SharedClipboardStore.promoteTemporary(id: first.id, storage: fixture.storage))
        let container = try makeContainer()
        let context = ModelContext(container)

        XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: fixture.storage))

        let imported = try context.fetch(FetchDescriptor<ClipboardItem>())
        XCTAssertEqual(imported.count, 2)
        let saved = try XCTUnwrap(imported.first { $0.id == first.id })
        let temporary = try XCTUnwrap(imported.first { $0.id == second.id })
        XCTAssertTrue(saved.isPermanent)
        XCTAssertNil(saved.expiresAt)
        XCTAssertTrue(temporary.isTemporary)
        XCTAssertEqual(temporary.expiresAt, second.expiresAt)
    }

    @MainActor
    func testPublishedTemporaryDeletionSurvivesTheNextSync() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        XCTAssertTrue(SharedClipboardStore.replaceTemporaryInbox(
            [makeClip(text: "Delete me", captured: .now, hours: 6, event: 301)],
            storage: fixture.storage
        ))
        let container = try makeContainer()
        let context = ModelContext(container)
        XCTAssertTrue(KeyboardHistorySync.synchronize(with: context, storage: fixture.storage))
        for item in try context.fetch(FetchDescriptor<ClipboardItem>()) {
            context.delete(item)
        }
        try context.save()
        XCTAssertTrue(KeyboardHistorySync.publishAppHistory(from: context, storage: fixture.storage))
        let reopened = ModelContext(container)

        XCTAssertTrue(KeyboardHistorySync.synchronize(with: reopened, storage: fixture.storage))

        XCTAssertTrue(try reopened.fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
        XCTAssertTrue(SharedClipboardStore.loadTemporaryInbox(storage: fixture.storage).isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ClipboardItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeClip(text: String, captured: Date, hours: Int, event: Int) -> SharedTemporaryClip {
        SharedTemporaryClip(
            id: UUID(), text: text, capturedAt: captured, kindRawValue: "text",
            expiresAt: captured.addingTimeInterval(Double(hours) * 3_600),
            pasteboardChangeCount: event
        )
    }

    private func makeFixture() throws -> StorageFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "SuperTeclado.SyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return StorageFixture(
            storage: .init(directoryURL: directory, fallbackDefaults: defaults, settingsDefaults: defaults),
            directory: directory, defaults: defaults, suite: suite
        )
    }

    private struct StorageFixture {
        let storage: SharedClipboardStore.Storage
        let directory: URL
        let defaults: UserDefaults
        let suite: String

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
