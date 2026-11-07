import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

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
