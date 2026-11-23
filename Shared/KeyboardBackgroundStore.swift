import Foundation
import ImageIO
import UIKit

/// Foto de fondo del tema «Mi foto», guardada en el App Group para que la lea el teclado.
enum KeyboardBackgroundStore {
    private static let fileName = "keyboard-background.jpg"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedClipboardStore.appGroupID)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static var hasImage: Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static var modificationDate: Date? {
        guard let url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    /// Reduce la foto antes de guardarla para que el teclado no se quede sin memoria.
    @discardableResult
    static func save(imageData: Data) -> Bool {
        guard let url,
              let image = downsample(imageData, maxPixelSize: 1_400),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(maxPixelSize: Int) -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url),
              let image = downsample(data, maxPixelSize: maxPixelSize) else { return nil }
        return UIImage(cgImage: image)
    }

    static func remove() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
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
}
