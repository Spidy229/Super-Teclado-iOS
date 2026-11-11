import Foundation
import SwiftData
import WidgetKit

@MainActor
enum KeyboardHistorySync {
    /// Elementos borrados en la app desde el último guardado, para no reimportarlos del teclado.
    private static var pendingDeletedIDs: Set<UUID> = []

    static func delete(_ item: ClipboardItem, from context: ModelContext) {
        pendingDeletedIDs.insert(item.id)
        context.delete(item)
    }

    /// Guarda los cambios de la app y sincroniza con el teclado en ambos sentidos.
    private enum SyncError: Error { case storageUnavailable }

    static func commit(_ context: ModelContext) throws {
        try context.save()
        // Persistir la intención antes de reimportar: un fallo no debe resucitar borrados.
        SharedClipboardStore.recordDeletion(of: pendingDeletedIDs)
        guard synchronize(with: context, excluding: pendingDeletedIDs) else {
            throw SyncError.storageUnavailable
        }
        pendingDeletedIDs = []
    }

    @discardableResult
    static func synchronize(
        with context: ModelContext, excluding deletedIDs: Set<UUID> = [],
        storage: SharedClipboardStore.Storage = .live
    ) -> Bool {
        guard SharedClipboardStore.canRead(storage: storage) else { return false }
        let deletions = SharedClipboardStore.pendingDeletedIDs(storage: storage).union(deletedIDs)
        guard applyKeyboardDeletions(deletions, in: context),
              importKeyboardClips(into: context, excluding: deletions, storage: storage),
              importTemporaryInbox(into: context, excluding: deletions, storage: storage),
              publishAppHistory(from: context, storage: storage) else { return false }
        // Acusar recibo solo cuando ambos historiales ya reflejan el borrado.
        SharedClipboardStore.forgetDeletion(of: deletions, storage: storage)
        return true
    }

    @discardableResult
    static func publishAppHistory(
        from context: ModelContext, storage: SharedClipboardStore.Storage = .live
    ) -> Bool {
        guard SharedClipboardStore.canRead(storage: storage) else { return false }
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.updatedAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return false }
        let previousTemporary = Dictionary(
            SharedClipboardStore.loadTemporaryInbox(storage: storage).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var imagePublicationFailed = false
        var referencedImages: Set<String> = []
        func publishedImage(for item: ClipboardItem) -> String? {
            guard let data = item.imageData else { return nil }
            guard let fileName = SharedClipboardStore.storeImageIfNeeded(data, for: item.id, storage: storage) else {
                imagePublicationFailed = true
                return nil
            }
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
                imageFileName: imageFileName,
                isSensitive: item.isSensitive ? true : nil
            )
        }
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
                pasteboardChangeCount: previousTemporary[item.id]?.pasteboardChangeCount,
                imageFileName: imageFileName,
                imageHash: imageFileName == nil ? nil : item.contentHash,
                isSensitive: item.isSensitive ? true : nil
            )
        }
        guard !imagePublicationFailed,
              SharedClipboardStore.save(clips, storage: storage),
              SharedClipboardStore.replaceTemporaryInbox(temporary, storage: storage) else { return false }
        SharedClipboardStore.pruneImages(keeping: referencedImages, storage: storage)
        // El widget muestra los fijados: se actualiza cuando cambia el historial.
        WidgetCenter.shared.reloadTimelines(ofKind: "PinnedClips")
        return true
    }

    private static func applyKeyboardDeletions(_ ids: Set<UUID>, in context: ModelContext) -> Bool {
        guard !ids.isEmpty else { return true }
        do {
            let items = try context.fetch(FetchDescriptor<ClipboardItem>())
            for item in items where ids.contains(item.id) { context.delete(item) }
            try context.save()
            return true
        } catch { return false }
    }

    private static func importKeyboardClips(
        into context: ModelContext, excluding deletedIDs: Set<UUID>, storage: SharedClipboardStore.Storage
    ) -> Bool {
        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let existing = try? context.fetch(descriptor) else { return false }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let existingByText = Dictionary(
            existing.compactMap { item in item.text.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        let existingByHash = Dictionary(
            existing.map { ($0.contentHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for clip in SharedClipboardStore.load(storage: storage) where !deletedIDs.contains(clip.id) {
            if let item = existingByID[clip.id] {
                item.isSensitive = item.isSensitive || clip.isSensitive == true
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
                guard let data = SharedClipboardStore.imageData(fileName: fileName, storage: storage) else { return false }
                let hash = ClipboardService.hash(data)
                if let item = existingByHash[hash] {
                    item.isSensitive = item.isSensitive || clip.isSensitive == true
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
                        contentHash: hash,
                        isSensitive: clip.isSensitive == true
                    )
                )
                continue
            }

            if let item = existingByText[clip.text] {
                item.isSensitive = item.isSensitive || clip.isSensitive == true
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
                    expiresAt: nil,
                    isSensitive: clip.isSensitive == true
                )
            )
        }
        do { try context.save(); return true } catch { return false }
    }

    private static func importTemporaryInbox(
        into context: ModelContext, excluding deletedIDs: Set<UUID>, storage: SharedClipboardStore.Storage
    ) -> Bool {
        let pending = SharedClipboardStore.loadTemporaryInbox(storage: storage).filter { !deletedIDs.contains($0.id) }
        guard !pending.isEmpty else { return true }

        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let existing = try? context.fetch(descriptor) else { return false }
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
            // nil significa «sin caducidad»; no inventar otra política al sincronizar.
            let expiration = clip.expiresAt

            if let item = existingByID[clip.id] {
                item.isSensitive = item.isSensitive || clip.isSensitive == true
                item.updatedAt = max(item.updatedAt, clip.capturedAt)
                if item.isTemporary { item.expiresAt = expiration }
                continue
            }

            var imageData: Data?
            var hash = ClipboardService.hash(Data(clip.text.utf8))
            if let fileName = clip.imageFileName {
                guard let data = SharedClipboardStore.imageData(fileName: fileName, storage: storage) else { return false }
                imageData = data
                hash = ClipboardService.hash(data)
            }

            let match = imageData == nil ? existingByText[clip.text] : existingByHash[hash]
            if let item = match {
                item.isSensitive = item.isSensitive || clip.isSensitive == true
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
                expiresAt: expiration,
                isSensitive: clip.isSensitive == true
            )
            context.insert(item)
            existingByID[clip.id] = item
            existingByHash[hash] = item
            if imageData == nil { existingByText[clip.text] = item }
        }

        do {
            try context.save()
            return true
        } catch {
            // Conservamos la bandeja compartida para reintentar en la próxima apertura.
            return false
        }
    }
}
