import Foundation
import SwiftData

enum ClipboardKind: String, Codable, CaseIterable {
    case text
    case image
    case link
    case email
    case phone

    var title: String {
        switch self {
        case .text: "Texto"
        case .image: "Imagen"
        case .link: "Enlace"
        case .email: "Correo"
        case .phone: "Teléfono"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .link: "link"
        case .email: "envelope"
        case .phone: "phone"
        }
    }
}

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var text: String?
    @Attribute(.externalStorage) var imageData: Data?
    var recognizedText: String?
    var kindRawValue: String
    var isFavorite: Bool
    var isPinned: Bool
    var tagsText: String
    var folderName: String?
    var colorTagRawValue: String?
    var contentHash: String
    var isTemporary: Bool = false
    var expiresAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        text: String? = nil,
        imageData: Data? = nil,
        recognizedText: String? = nil,
        kind: ClipboardKind,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        tagsText: String = "",
        folderName: String? = nil,
        colorTagRawValue: String? = nil,
        contentHash: String,
        isTemporary: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.text = text
        self.imageData = imageData
        self.recognizedText = recognizedText
        self.kindRawValue = kind.rawValue
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.tagsText = tagsText
        self.folderName = folderName
        self.colorTagRawValue = colorTagRawValue
        self.contentHash = contentHash
        self.isTemporary = isTemporary
        self.expiresAt = expiresAt
    }

    var kind: ClipboardKind {
        get { ClipboardKind(rawValue: kindRawValue) ?? .text }
        set { kindRawValue = newValue.rawValue }
    }

    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var colorTag: SharedClipColor? {
        get { colorTagRawValue.flatMap { SharedClipColor(rawValue: $0) } }
        set { colorTagRawValue = newValue?.rawValue }
    }

    var searchableText: String {
        [text, recognizedText, tagsText]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var previewText: String {
        if let text, !text.isEmpty { return text }
        if let recognizedText, !recognizedText.isEmpty { return recognizedText }
        return "Imagen guardada"
    }

    var isPermanent: Bool { !isTemporary }

    func promoteToPermanent() {
        isTemporary = false
        expiresAt = nil
        updatedAt = .now
    }
}
