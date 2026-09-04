import SwiftUI

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

                Text(item.previewText)
                    .font(.body)
                    .lineLimit(item.kind == .image ? 2 : 3)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(item.updatedAt, style: .relative)
                    if item.isTemporary, let expiresAt = item.expiresAt {
                        Label {
                            Text(expiresAt, style: .relative)
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
        if let data = item.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.title2)
                .foregroundStyle(.cyan)
        }
    }
}
