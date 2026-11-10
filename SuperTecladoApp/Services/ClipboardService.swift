import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers

struct ClipboardDraft {
    let text: String?
    let imageData: Data?
    let kind: ClipboardKind
    let contentHash: String
}

enum ClipboardReadResult {
    case content(ClipboardDraft)
    case empty
    case unsupported
}

@MainActor
enum ClipboardService {
    static func readCurrent(from pasteboard: UIPasteboard = .general) -> ClipboardReadResult {
        if let image = pasteboard.image,
           let data = normalizedJPEG(from: image) {
            return .content(
                ClipboardDraft(
                    text: nil,
                    imageData: data,
                    kind: .image,
                    contentHash: hash(data)
                )
            )
        }

        if let originalText = pasteboard.string {
            let meaningfulText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !meaningfulText.isEmpty else { return .empty }
            let data = Data(originalText.utf8)
            return .content(
                ClipboardDraft(
                    text: originalText,
                    imageData: nil,
                    kind: detectKind(for: meaningfulText),
                    contentHash: hash(data)
                )
            )
        }

        return pasteboard.hasStrings || pasteboard.hasImages ? .unsupported : .empty
    }

    static func copy(_ item: ClipboardItem, localOnly: Bool) -> Bool {
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if localOnly {
            options[.localOnly] = true
        }

        if let imageData = item.imageData {
            UIPasteboard.general.setItems(
                [[UTType.jpeg.identifier: imageData]],
                options: options
            )
            return true
        }

        if let text = item.text {
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: options
            )
            return true
        }

        return false
    }

    static func isLikelyOneTimeCode(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedJPEG(from image: UIImage) -> Data? {
        let maximumDimension: CGFloat = 2_048
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, maximumDimension / longestSide)
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * scale).rounded(.down)),
            height: max(1, (pixelSize.height * scale).rounded(.down))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalizedImage.jpegData(compressionQuality: 0.82)
    }

    private static func detectKind(for text: String) -> ClipboardKind {
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return .link
        }

        if text.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return .email
        }

        if text.range(
            of: #"^\+?[0-9][0-9 ()-]{6,}$"#,
            options: .regularExpression
        ) != nil {
            return .phone
        }

        return .text
    }
}

