import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

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

    var isImage: Bool { imageFileName != nil }
    var isSaved: Bool { source == .saved }

    init(saved clip: SharedClipboardClip) {
        id = clip.id
        text = clip.text
        imageFileName = clip.imageFileName
        kindRawValue = clip.kindRawValue
        date = clip.updatedAt
        source = .saved
        folderName = clip.folderName
    }

    init(recent clip: SharedTemporaryClip) {
        id = clip.id
        text = clip.text
        imageFileName = clip.imageFileName
        kindRawValue = clip.kindRawValue
        date = clip.capturedAt
        source = .recent
        folderName = nil
    }
}

enum ClipImageProcessing {
    /// Lee la primera representación de imagen del portapapeles sin decodificarla.
    static func pasteboardImageData(_ pasteboard: UIPasteboard) -> Data? {
        for type in pasteboard.types {
            guard let utType = UTType(type), utType.conforms(to: .image) else { continue }
            if let data = pasteboard.data(forPasteboardType: type) { return data }
        }
        return nil
    }

    /// Reduce la imagen con ImageIO para no superar el límite de memoria de la extensión.
    static func jpegThumbnail(from data: Data, maxPixelSize: Int) -> Data? {
        guard let image = downsampledImage(from: data, maxPixelSize: maxPixelSize) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }

    static func downsampledImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
enum ClipThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    static func thumbnail(for fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        guard let data = SharedClipboardStore.imageData(fileName: fileName),
              let image = ClipImageProcessing.downsampledImage(from: data, maxPixelSize: 360) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: image)
        cache.setObject(thumbnail, forKey: fileName as NSString)
        return thumbnail
    }
}
