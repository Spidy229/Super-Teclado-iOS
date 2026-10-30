import SwiftUI

private enum ClipFilter: Hashable {
    case all
    case saved
    case recent
    case text
    case links
    case images
    case folder(String)

    var title: String {
        switch self {
        case .all: "Todo"
        case .saved: "Fijados"
        case .recent: "Recientes"
        case .text: "Texto"
        case .links: "Enlaces"
        case .images: "Imágenes"
        case .folder(let name): name
        }
    }

    var symbol: String? {
        switch self {
        case .saved: "pin.fill"
        case .recent: "clock"
        case .links: "link"
        case .images: "photo"
        case .folder: "folder"
        default: nil
        }
    }

    func matches(_ clip: KeyboardClip) -> Bool {
        switch self {
        case .all: true
        case .saved: clip.isSaved
        case .recent: !clip.isSaved
        case .text: !clip.isImage && clip.kindRawValue != "link"
        case .links: clip.kindRawValue == "link"
        case .images: clip.isImage
        case .folder(let name): clip.folderName == name
        }
    }
}

/// Cabecera del portapapeles en la barra superior.
struct ClipboardHeaderView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            StripButton(symbol: "arrow.left", label: "Volver al teclado") { engine.closePanel() }
            Text(engine.isEditingClips ? editingTitle : "Portapapeles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            if engine.hasFullAccess {
                if !engine.isEditingClips {
                    Toggle("Portapapeles activado", isOn: Binding(
                        get: { engine.clipboardEnabled },
                        set: { engine.setClipboardEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(palette.accent)
                    .scaleEffect(0.8)
                }
                StripButton(
                    symbol: engine.isEditingClips ? "checkmark" : "pencil",
                    isActive: engine.isEditingClips,
                    label: engine.isEditingClips ? "Terminar edición" : "Editar"
                ) {
                    engine.isEditingClips.toggle()
                    engine.selectedClipIDs = []
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editingTitle: String {
        let count = engine.selectedClipIDs.count
        return count == 0 ? "Selecciona elementos" : (count == 1 ? "1 seleccionado" : "\(count) seleccionados")
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    @State private var activeFilter: ClipFilter = .all
    @State private var focusedClip: KeyboardClip?

    private var filters: [ClipFilter] {
        var result: [ClipFilter] = [.all, .saved, .recent, .text, .links, .images]
        result += engine.folders.map(ClipFilter.folder)
        return result
    }

    private var savedClips: [KeyboardClip] { engine.savedClips.filter { activeFilter.matches($0) } }
    private var recentClips: [KeyboardClip] { engine.recentClips.filter { activeFilter.matches($0) } }

    var body: some View {
        VStack(spacing: 0) {
            if !engine.hasFullAccess { fullAccessBanner }
            filterChips
            content
            if engine.isEditingClips { editingBar }
        }
        .overlay { if let focusedClip { actionMenu(for: focusedClip) } }
        .onChange(of: engine.folders) { _, folders in
            if case .folder(let name) = activeFilter, !folders.contains(name) { activeFilter = .all }
        }
    }

    @ViewBuilder
    private var content: some View {
        if savedClips.isEmpty && recentClips.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !savedClips.isEmpty {
                        sectionHeader("Fijados", symbol: "pin.fill")
                        grid(savedClips)
                    }
                    if !recentClips.isEmpty {
                        sectionHeader("Recientes", symbol: "clock")
                        grid(recentClips)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }

    private var fullAccessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text("Activa «Permitir acceso total» para guardar lo que copias")
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(palette.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.self) { item in
                    Button { activeFilter = item } label: {
                        HStack(spacing: 4) {
                            if let symbol = item.symbol { Image(systemName: symbol).font(.system(size: 11)) }
                            Text(item.title).font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(activeFilter == item ? palette.accentText : palette.text)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(activeFilter == item ? palette.accent : palette.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.secondaryText)
            .padding(.top, 4)
            .padding(.leading, 2)
    }

    private func grid(_ clips: [KeyboardClip]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(clips) { clip in
                ClipTileView(
                    clip: clip,
                    isEditing: engine.isEditingClips,
                    isSelected: engine.selectedClipIDs.contains(clip.id)
                )
                .onTapGesture {
                    if engine.isEditingClips {
                        engine.toggleClipSelection(clip)
                    } else {
                        engine.keyFeedback(.character)
                        engine.useClip(clip)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    guard !engine.isEditingClips else { return }
                    engine.keyFeedback(.modifier)
                    focusedClip = clip
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            if engine.hasFullAccess && !engine.clipboardEnabled {
                Image(systemName: "clipboard")
                    .font(.system(size: 34, weight: .light))
                Text("El portapapeles está desactivado")
                    .font(.system(size: 15, weight: .semibold))
                Text("Actívalo para guardar automáticamente lo que copies.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                Button("Activar portapapeles") { engine.setClipboardEnabled(true) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accentText)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(palette.accent, in: Capsule())
                    .buttonStyle(.plain)
            } else {
                Image(systemName: activeFilter == .all ? "doc.on.clipboard" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 34, weight: .light))
                Text(activeFilter == .all ? "Lo que copies aparecerá aquí" : "No hay elementos en «\(activeFilter.title)»")
                    .font(.system(size: 15, weight: .semibold))
                Text("Mantén pulsado un elemento para fijarlo y conservarlo.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.text)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editingBar: some View {
        let selected = engine.selectedClips
        let allClips = engine.savedClips.filter { activeFilter.matches($0) } + engine.recentClips.filter { activeFilter.matches($0) }
        return HStack(spacing: 6) {
            barButton(
                selected.count == allClips.count && !allClips.isEmpty ? "Ninguno" : "Todos",
                symbol: "checklist"
            ) {
                if selected.count == allClips.count {
                    engine.selectedClipIDs = []
                } else {
                    engine.selectedClipIDs = Set(allClips.map(\.id))
                }
            }
            Spacer(minLength: 0)
            if selected.isEmpty {
                barButton("Borrar recientes", symbol: "clock.badge.xmark", destructive: true) {
                    engine.clearRecents()
                }
                .disabled(engine.recentClips.isEmpty)
            } else {
                barButton("Fijar", symbol: "pin") {
                    engine.pinClips(selected)
                    engine.selectedClipIDs = []
                }
                .disabled(!selected.contains { !$0.isSaved })
                barButton("Eliminar", symbol: "trash", destructive: true) {
                    engine.deleteClips(selected)
                    engine.selectedClipIDs = []
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(palette.specialKey.opacity(0.6))
    }

    private func barButton(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(destructive ? Color.red : palette.text)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(palette.chip, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func actionMenu(for clip: KeyboardClip) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .onTapGesture { focusedClip = nil }
            VStack(spacing: 10) {
                Group {
                    if clip.isImage {
                        Label("Imagen", systemImage: "photo")
                    } else {
                        Text(clip.text)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    menuButton(clip.isSaved ? "Desfijar" : "Fijar", symbol: clip.isSaved ? "pin.slash" : "pin") {
                        engine.togglePin(clip)
                    }
                    menuButton(clip.isImage ? "Copiar" : "Pegar", symbol: clip.isImage ? "doc.on.doc" : "arrow.down.doc") {
                        engine.useClip(clip)
                    }
                    if !clip.isImage {
                        menuButton("Copiar", symbol: "doc.on.doc") { engine.copyClip(clip) }
                    }
                    menuButton("Eliminar", symbol: "trash", destructive: true) { engine.deleteClips([clip]) }
                }
            }
            .padding(12)
            .background(palette.popup, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(10)
        }
        .transition(.opacity)
    }

    private func menuButton(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            focusedClip = nil
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(destructive ? Color.red : palette.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ClipTileView: View {
    @Environment(\.keyboardPalette) private var palette
    let clip: KeyboardClip
    let isEditing: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fileName = clip.imageFileName {
                ClipThumbnailView(fileName: fileName)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(clip.text)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: SharedClipboardStore.symbol(forKind: clip.kindRawValue))
                Text(clip.date, format: .relative(presentation: .named))
                    .lineLimit(1)
                if let folder = clip.folderName {
                    Text("· \(folder)").lineLimit(1)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.secondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(palette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                    .padding(6)
            } else if clip.isSaved {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.accent)
                    .padding(8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 2)
        }
        .shadow(color: palette.shadow.opacity(0.5), radius: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Toca para pegar. Mantén pulsado para más opciones.")
    }
}

struct ClipThumbnailView: View {
    @Environment(\.keyboardPalette) private var palette
    let fileName: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                palette.specialKey
                Image(systemName: "photo").foregroundStyle(palette.secondaryText)
            }
        }
        .clipped()
        .task(id: fileName) { image = ClipThumbnailCache.thumbnail(for: fileName) }
    }
}
