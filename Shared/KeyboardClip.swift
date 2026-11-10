import Foundation

/// Copia que presenta el teclado, con su caducidad para no usar instantáneas vencidas.
struct KeyboardClip: Identifiable, Hashable {
    enum Source: Hashable {
        case saved
        case recent
    }

    let id: UUID
    let text: String
    let imageFileName: String?
    let kindRawValue: String
    let date: Date
    let source: Source
    let folderName: String?
    let isSensitive: Bool
    let expiresAt: Date?

    var isImage: Bool { imageFileName != nil }
    var isSaved: Bool { source == .saved }
    var linkDomain: String? { kindRawValue == "link" ? ClipboardClassifier.linkDomain(text) : nil }

    func isExpired(at date: Date = .now) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }

    init(saved clip: SharedClipboardClip) {
        id = clip.id
        text = clip.text
        imageFileName = clip.imageFileName
        kindRawValue = clip.kindRawValue
        date = clip.updatedAt
        source = .saved
        folderName = clip.folderName
        isSensitive = clip.isSensitive == true
        expiresAt = nil
    }

    init(recent clip: SharedTemporaryClip) {
        id = clip.id
        text = clip.text
        imageFileName = clip.imageFileName
        kindRawValue = clip.kindRawValue
        date = clip.capturedAt
        source = .recent
        folderName = nil
        isSensitive = clip.isSensitive == true
        expiresAt = clip.expiresAt
    }
}
