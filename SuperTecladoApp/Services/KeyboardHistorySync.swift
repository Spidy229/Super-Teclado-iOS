import Foundation
import SwiftData

@MainActor
enum KeyboardHistorySync {
    /// Elementos borrados en la app desde el último guardado, para no reimportarlos del teclado.
    private static var pendingDeletedIDs: Set<UUID> = []

    static func delete(_ item: ClipboardItem, from context: ModelContext) {
        pendingDeletedIDs.insert(item.id)
        context.delete(item)
    }

    /// Guarda los cambios de la app y sincroniza con el teclado en ambos sentidos.
    static func commit(_ context: ModelContext) throws {
        try context.save()
        let deletedIDs = pendingDeletedIDs
        pendingDeletedIDs = []
        synchronize(with: context, excluding: deletedIDs)
    }

    static func synchronize(with context: ModelContext, excluding deletedIDs: Set<UUID> = []) {
        applyKeyboardDeletions(in: context)
        importKeyboardClips(into: context, excluding: deletedIDs)
        importTemporaryInbox(into: context, excluding: deletedIDs)
        publishAppHistory(from: context)
    }

    static func publishAppHistory(from context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return }

        var referencedImages: Set<String> = []
        func publishedImage(for item: ClipboardItem) -> String? {
            guard let data = item.imageData,
                  let fileName = SharedClipboardStore.storeImageIfNeeded(data, for: item.id) else { return nil }
            referencedImages.insert(fileName)
            return fileName
        }

        let clips = items.compactMap { item -> SharedClipboardClip? in
            guard item.isPermanent else { return nil }
            let imageFileName = publishedImage(for: item)
            let value = item.text ?? item.recognizedText ?? ""
            guard !value.isEmpty || imageFileName != nil else { return nil }
            return SharedClipboardClip(
                id: item.id,
                text: value,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                kindRawValue: item.kindRawValue,
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                folderName: item.folderName,
                colorTagRawValue: item.colorTagRawValue,
                imageFileName: imageFileName
            )
        }
        SharedClipboardStore.save(clips)

        let temporary = items.compactMap { item -> SharedTemporaryClip? in
            guard item.isTemporary else { return nil }
            let imageFileName = publishedImage(for: item)
            let value = item.text ?? item.recognizedText ?? ""
            guard !value.isEmpty || imageFileName != nil else { return nil }
            return SharedTemporaryClip(
                id: item.id,
                text: value,
                capturedAt: item.updatedAt,
                kindRawValue: item.kindRawValue,
                expiresAt: item.expiresAt,
                imageFileName: imageFileName,
                imageHash: imageFileName == nil ? nil : item.contentHash
            )
        }
        SharedClipboardStore.replaceTemporaryInbox(temporary)
        SharedClipboardStore.pruneImages(keeping: referencedImages)
    }

    private static func applyKeyboardDeletions(in context: ModelContext) {
        let ids = SharedClipboardStore.consumeDeletedIDs()
        guard !ids.isEmpty else { return }
        let items = (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []
        for item in items where ids.contains(item.id) {
            context.delete(item)
        }
        try? context.save()
    }

    private static func importKeyboardClips(into context: ModelContext, excluding deletedIDs: Set<UUID>) {
        let descriptor = FetchDescriptor<ClipboardItem>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let existingByText = Dictionary(
            existing.compactMap { item in item.text.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        let existingByHash = Dictionary(
            existing.map { ($0.contentHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for clip in SharedClipboardStore.load() where !deletedIDs.contains(clip.id) {
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

            if let fileName = clip.imageFileName {
                guard let data = SharedClipboardStore.imageData(fileName: fileName) else { continue }
                let hash = ClipboardService.hash(data)
                if let item = existingByHash[hash] {
                    item.updatedAt = max(item.updatedAt, clip.updatedAt)
                    item.isPinned = clip.isPinned
                    item.isTemporary = false
                    item.expiresAt = nil
                    continue
                }
                context.insert(
                    ClipboardItem(
                        id: clip.id,
                        createdAt: clip.createdAt,
                        updatedAt: clip.updatedAt,
                        imageData: data,
                        recognizedText: clip.text.isEmpty ? nil : clip.text,
                        kind: .image,
                        isFavorite: clip.isFavorite,
                        isPinned: clip.isPinned,
                        folderName: clip.folderName,
                        colorTagRawValue: clip.colorTagRawValue,
                        contentHash: hash
                    )
                )
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

    private static func importTemporaryInbox(into context: ModelContext, excluding deletedIDs: Set<UUID>) {
        let pending = SharedClipboardStore.loadTemporaryInbox().filter { !deletedIDs.contains($0.id) }
        guard !pending.isEmpty else { return }

        let descriptor = FetchDescriptor<ClipboardItem>()
        let existing = (try? context.fetch(descriptor)) ?? []
        var existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var existingByText = Dictionary(
            existing.compactMap { item in item.text.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        var existingByHash = Dictionary(
            existing.map { ($0.contentHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for clip in pending {
            let expiration = clip.expiresAt ?? ClipboardRetentionPolicy.expirationDate(
                hours: SharedClipboardStore.temporaryRetentionHours,
                from: clip.capturedAt
            )

            if let item = existingByID[clip.id] {
                item.updatedAt = max(item.updatedAt, clip.capturedAt)
                if item.isTemporary { item.expiresAt = expiration }
                continue
            }

            var imageData: Data?
            var hash = ClipboardService.hash(Data(clip.text.utf8))
            if let fileName = clip.imageFileName {
                guard let data = SharedClipboardStore.imageData(fileName: fileName) else { continue }
                imageData = data
                hash = ClipboardService.hash(data)
            }

            let match = imageData == nil ? existingByText[clip.text] : existingByHash[hash]
            if let item = match {
                item.updatedAt = max(item.updatedAt, clip.capturedAt)
                if item.isTemporary { item.expiresAt = expiration }
                continue
            }

            let item = ClipboardItem(
                id: clip.id,
                createdAt: clip.capturedAt,
                updatedAt: clip.capturedAt,
                text: imageData == nil ? clip.text : nil,
                imageData: imageData,
                kind: imageData == nil ? (ClipboardKind(rawValue: clip.kindRawValue) ?? .text) : .image,
                contentHash: hash,
                isTemporary: true,
                expiresAt: expiration
            )
            context.insert(item)
            existingByID[clip.id] = item
            existingByHash[hash] = item
            if imageData == nil { existingByText[clip.text] = item }
        }

        do {
            try context.save()
        } catch {
            // Conservamos la bandeja compartida para reintentar en la próxima apertura.
        }
    }
}
