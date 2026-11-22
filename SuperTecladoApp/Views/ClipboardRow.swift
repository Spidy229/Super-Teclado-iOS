import SwiftUI
import UIKit

@MainActor
private enum AppThumbnailCache {
    private static let cache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func image(for id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    static func store(_ image: UIImage, for id: UUID) {
        cache.setObject(image, forKey: id as NSUUID)
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            preview
                .frame(width: 54, height: 54)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label(item.kind.title, systemImage: item.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if item.isTemporary {
                        Label("Temporal", systemImage: "clock")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    }

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    if let color = item.colorTag {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(color.color)
                            .accessibilityLabel("Etiqueta \(color.title)")
                    }
                }

                if item.isSensitive {
                    Label("Contenido privado", systemImage: "lock.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    // Sin `.textSelection(.enabled)` en filas de lista: en iOS instala gestos de
                    // selección que compiten con los toques y el scroll (la selección sigue en Detalle).
                    Text(item.previewText)
                        .font(.body)
                        .lineLimit(item.kind == .image ? 2 : 3)
                }

                HStack(spacing: 8) {
                    // Texto formateado estático (no `style: .relative`), evitando redibujar todas
                    // las filas cada segundo mientras el usuario desplaza o toca la lista.
                    Text(item.updatedAt.formatted(.relative(presentation: .named)))
                    if item.isTemporary, let expiresAt = item.expiresAt {
                        Label {
                            Text(expiresAt.formatted(.relative(presentation: .named)))
                        } icon: {
                            Image(systemName: "hourglass")
                        }
                    }
                    if item.isPermanent, let folder = item.folderName {
                        Label(folder, systemImage: "folder.fill")
                    }
                    ForEach(item.isPermanent ? Array(item.tags.prefix(2)) : [], id: \.self) { tag in
                        Text("#\(tag)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .image {
            ClipboardThumbnailView(item: item)
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.title2)
                .foregroundStyle(.cyan)
        }
    }
}

private struct ClipboardThumbnailView: View {
    let item: ClipboardItem
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(.cyan)
            }
        }
        .task(id: item.id) {
            if let cached = AppThumbnailCache.image(for: item.id) {
                thumbnail = cached
                return
            }
            guard let data = item.imageData else { return }
            let id = item.id
            let cgImage = await Task.detached(priority: .userInitiated) {
                ClipImageProcessing.downsampledImage(from: data, maxPixelSize: 162)
            }.value
            guard !Task.isCancelled, let cgImage else { return }
            let image = UIImage(cgImage: cgImage)
            AppThumbnailCache.store(image, for: id)
            thumbnail = image
        }
    }
}
