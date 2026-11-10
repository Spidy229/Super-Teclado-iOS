import UIKit

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
