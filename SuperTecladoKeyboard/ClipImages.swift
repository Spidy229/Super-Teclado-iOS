import UIKit

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

    var isImage: Bool { imageFileName != nil }
    var isSaved: Bool { source == .saved }
    var linkDomain: String? { kindRawValue == "link" ? ClipboardClassifier.linkDomain(text) : nil }

    init(saved clip: SharedClipboardClip) {
        id = clip.id
        text = clip.text
        imageFileName = clip.imageFileName
        kindRawValue = clip.kindRawValue
        date = clip.updatedAt
        source = .saved
        folderName = clip.folderName
        isSensitive = clip.isSensitive == true
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
