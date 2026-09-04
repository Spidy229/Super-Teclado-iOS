import Foundation
import SwiftData

@MainActor
enum KeyboardHistorySync {
    static func synchronize(with context: ModelContext) {
        importKeyboardClips(into: context)
        importTemporaryInbox(into: context)
        publishAppHistory(from: context)
    }

    static func publishAppHistory(from context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return }

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
        SharedClipboardStore.save(clips)

        let temporary = items.compactMap { item -> SharedTemporaryClip? in
            guard item.isTemporary, let value = item.text, !value.isEmpty else { return nil }
            return SharedTemporaryClip(
                id: item.id,
                text: value,
                capturedAt: item.updatedAt,
                kindRawValue: item.kindRawValue,
                expiresAt: item.expiresAt
            )
        }
        SharedClipboardStore.replaceTemporaryInbox(temporary)
    }

    private static func importKeyboardClips(into context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardItem>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let existingByText = Dictionary(
            existing.compactMap { item in item.text.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )

        for clip in SharedClipboardStore.load() {
            if let item = existingByID[clip.id] {
                if clip.updatedAt > item.updatedAt {
                    item.updatedAt = clip.updatedAt
                    item.isFavorite = clip.isFavorite
                    item.isPinned = clip.isPinned
                    item.folderName = clip.folderName
                    item.colorTagRawValue = clip.colorTagRawValue
                }
                item.isTemporary = false
                item.expiresAt = nil
                continue
            }
            if let item = existingByText[clip.text] {
                item.updatedAt = max(item.updatedAt, clip.updatedAt)
                item.isFavorite = clip.isFavorite
                item.isPinned = clip.isPinned
                item.folderName = clip.folderName
                item.colorTagRawValue = clip.colorTagRawValue
                item.isTemporary = false
                item.expiresAt = nil
                continue
            }
            let data = Data(clip.text.utf8)
            context.insert(
                ClipboardItem(
                    id: clip.id,
                    createdAt: clip.createdAt,
                    updatedAt: clip.updatedAt,
                    text: clip.text,
                    kind: ClipboardKind(rawValue: clip.kindRawValue) ?? .text,
                    isFavorite: clip.isFavorite,
                    isPinned: clip.isPinned,
                    folderName: clip.folderName,
                    colorTagRawValue: clip.colorTagRawValue,
                    contentHash: ClipboardService.hash(data),
                    isTemporary: false,
                    expiresAt: nil
                )
            )
        }
        try? context.save()
    }

    private static func importTemporaryInbox(into context: ModelContext) {
        let pending = SharedClipboardStore.loadTemporaryInbox()
        guard !pending.isEmpty else { return }

        let descriptor = FetchDescriptor<ClipboardItem>()
        let existing = (try? context.fetch(descriptor)) ?? []
        var existingByText = Dictionary(
            existing.compactMap { item in item.text.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )

        for clip in pending {
            if let item = existingByText[clip.text] {
                item.updatedAt = max(item.updatedAt, clip.capturedAt)
                if item.isTemporary {
                    item.expiresAt = ClipboardRetentionPolicy.expirationDate(
                        hours: ClipboardRetentionPolicy.defaultTemporaryHours,
                        from: clip.capturedAt
                    )
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
                expiresAt: ClipboardRetentionPolicy.expirationDate(
                    hours: ClipboardRetentionPolicy.defaultTemporaryHours,
                    from: clip.capturedAt
                )
            )
            context.insert(item)
            existingByText[clip.text] = item
        }

        do {
            try context.save()
        } catch {
            // Conservamos la bandeja compartida para reintentar en la próxima apertura.
        }
    }
}
