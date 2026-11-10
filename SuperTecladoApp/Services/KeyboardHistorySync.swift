import Foundation
import SwiftData

@MainActor
enum KeyboardHistorySync {
    @discardableResult
    static func synchronize(
        with context: ModelContext,
        storage: SharedClipboardStore.Storage = .live
    ) -> Bool {
        guard SharedClipboardStore.canRead(storage: storage) else { return false }
        do {
            try importKeyboardClips(into: context, storage: storage)
            try importTemporaryInbox(into: context, storage: storage)
            try context.save()
            return publishAppHistory(from: context, storage: storage)
        } catch {
            // Do not replace the shared inbox if its import could not be persisted.
            return false
        }
    }

    @discardableResult
    static func publishAppHistory(
        from context: ModelContext,
        lastPasteboardChangeCount: Int? = nil,
        storage: SharedClipboardStore.Storage = .live
    ) -> Bool {
        guard SharedClipboardStore.canRead(storage: storage) else { return false }
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return false }

        let clips = items.compactMap { item -> SharedClipboardClip? in
            guard item.isPermanent else { return nil }
            let value = item.text ?? item.recognizedText
            guard let value, !value.isEmpty else { return nil }
            return SharedClipboardClip(
                id: item.id,
                text: value,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                kindRawValue: item.kindRawValue,
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                folderName: item.folderName,
                colorTagRawValue: item.colorTagRawValue
            )
        }
        guard SharedClipboardStore.save(clips, storage: storage) else { return false }

        let temporary = items.compactMap { item -> SharedTemporaryClip? in
            guard item.isTemporary, let value = item.text, !value.isEmpty else { return nil }
            return SharedTemporaryClip(
                id: item.id,
                text: value,
                capturedAt: item.updatedAt,
                kindRawValue: item.kindRawValue,
                expiresAt: item.expiresAt,
                pasteboardChangeCount: item.pasteboardChangeCount
            )
        }
        return SharedClipboardStore.replaceTemporaryInbox(
            temporary, lastPasteboardChangeCount: lastPasteboardChangeCount, storage: storage
        )
    }

    private static func importKeyboardClips(
        into context: ModelContext,
        storage: SharedClipboardStore.Storage
    ) throws {
        let existing = try context.fetch(FetchDescriptor<ClipboardItem>())
        var existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var permanentByText = Dictionary(
            existing.filter(\.isPermanent).compactMap { item in item.text.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )

        for clip in SharedClipboardStore.load(storage: storage) {
            if let item = existingByID[clip.id] ?? permanentByText[clip.text] {
                if clip.updatedAt > item.updatedAt {
                    item.updatedAt = clip.updatedAt
                    item.isFavorite = clip.isFavorite
                    item.isPinned = clip.isPinned
                    item.folderName = clip.folderName
                    item.colorTagRawValue = clip.colorTagRawValue
                }
                item.isTemporary = false
                item.expiresAt = nil
                permanentByText[clip.text] = item
                continue
            }
            let item = ClipboardItem(
                id: clip.id,
                createdAt: clip.createdAt,
                updatedAt: clip.updatedAt,
                text: clip.text,
                kind: ClipboardKind(rawValue: clip.kindRawValue) ?? .text,
                isFavorite: clip.isFavorite,
                isPinned: clip.isPinned,
                folderName: clip.folderName,
                colorTagRawValue: clip.colorTagRawValue,
                contentHash: ClipboardService.hash(Data(clip.text.utf8)),
                isTemporary: false
            )
            context.insert(item)
            existingByID[clip.id] = item
            permanentByText[clip.text] = item
        }
    }

    private static func importTemporaryInbox(
        into context: ModelContext,
        storage: SharedClipboardStore.Storage
    ) throws {
        let pending = SharedClipboardStore.loadTemporaryInbox(storage: storage)
        guard !pending.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<ClipboardItem>())
        var existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for clip in pending {
            if let item = existingByID[clip.id] {
                // A promoted item stays permanent even if an older inbox still contains it.
                guard item.isTemporary else { continue }
                if clip.capturedAt >= item.updatedAt {
                    item.updatedAt = clip.capturedAt
                    item.expiresAt = clip.expiresAt
                    item.pasteboardChangeCount = clip.pasteboardChangeCount
                }
                continue
            }

            let item = ClipboardItem(
                id: clip.id,
                createdAt: clip.capturedAt,
                updatedAt: clip.capturedAt,
                text: clip.text,
                kind: ClipboardKind(rawValue: clip.kindRawValue) ?? .text,
                contentHash: ClipboardService.hash(Data(clip.text.utf8)),
                isTemporary: true,
                expiresAt: clip.expiresAt,
                pasteboardChangeCount: clip.pasteboardChangeCount
            )
            context.insert(item)
            existingByID[clip.id] = item
        }
    }
}
