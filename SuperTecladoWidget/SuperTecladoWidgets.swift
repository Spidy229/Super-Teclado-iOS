import AppIntents
import SwiftUI
import WidgetKit

@main
struct SuperTecladoWidgets: WidgetBundle {
    var body: some Widget {
        PinnedClipsWidget()
        CopyLatestControl()
    }
}

struct WidgetClip: Identifiable {
    let id: UUID
    let text: String
    let isSaved: Bool
}

struct PinnedClipsEntry: TimelineEntry {
    let date: Date
    let clips: [WidgetClip]
}

struct PinnedClipsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedClipsEntry {
        PinnedClipsEntry(date: .now, clips: [
            WidgetClip(id: UUID(), text: "Mi dirección de correo", isSaved: true),
            WidgetClip(id: UUID(), text: "Calle Mayor 1, Madrid", isSaved: true)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedClipsEntry) -> Void) {
        completion(PinnedClipsEntry(date: .now, clips: Self.loadClips()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedClipsEntry>) -> Void) {
        let entry = PinnedClipsEntry(date: .now, clips: Self.loadClips())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    /// Primero los fijados y después los recientes; nunca los privados ni las imágenes.
    static func loadClips() -> [WidgetClip] {
        let saved = SharedClipboardStore.load()
            .filter { !$0.isImage && $0.isSensitive != true }
            .map { WidgetClip(id: $0.id, text: $0.text, isSaved: true) }
        let recent = SharedClipboardStore.loadTemporaryInbox()
            .filter { !$0.isImage && $0.isSensitive != true }
            .map { WidgetClip(id: $0.id, text: $0.text, isSaved: false) }
        return Array((saved + recent).prefix(6))
    }
}

struct PinnedClipsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PinnedClips", provider: PinnedClipsProvider()) { entry in
            PinnedClipsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Portapapeles")
        .description("Tus elementos fijados: toca uno para copiarlo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PinnedClipsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PinnedClipsEntry

    private var visibleClips: [WidgetClip] {
        switch family {
        case .systemSmall: Array(entry.clips.prefix(2))
        case .systemMedium: Array(entry.clips.prefix(3))
        default: entry.clips
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Portapapeles", systemImage: "doc.on.clipboard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if visibleClips.isEmpty {
                Spacer()
                Text("Fija elementos en el teclado para tenerlos aquí.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(visibleClips) { clip in
                    Button(intent: CopyClipIntent(clipID: clip.id.uuidString)) {
                        HStack(spacing: 6) {
                            Image(systemName: clip.isSaved ? "pin.fill" : "clock")
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                            Text(clip.text.replacingOccurrences(of: "\n", with: " "))
                                .font(.footnote)
                                .lineLimit(family == .systemSmall ? 2 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Botón del Centro de control (iOS 18): copia lo último del historial.
struct CopyLatestControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.spidy229.superteclado.copylatest") {
            ControlWidgetButton(action: CopyLatestClipIntent()) {
                Label("Copiar lo último", systemImage: "doc.on.clipboard")
            }
        }
        .displayName("Copiar lo último")
        .description("Copia el texto más reciente del historial de Super Teclado.")
    }
}
