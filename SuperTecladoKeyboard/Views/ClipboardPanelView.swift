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

/// Qué muestra la tarjeta de opciones de un elemento.
private enum ClipMenuMode {
    case actions
    case pasteAs
    case folders
}

/// Cabecera del portapapeles en la barra superior.
struct ClipboardHeaderView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            PanelBackButton { engine.closePanel() }
            Text(engine.isEditingClips ? editingTitle : "Portapapeles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            if engine.hasFullAccess {
                if !engine.isEditingClips {
                    StripButton(symbol: "magnifyingglass", label: "Buscar en el portapapeles") {
                        engine.openClipboardSearch()
                    }
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
                    label: engine.isEditingClips ? "Terminar edición" : "Seleccionar varios"
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
    @State private var menuMode: ClipMenuMode = .actions
    @State private var fullTextClip: KeyboardClip?
    @State private var revealedIDs: Set<UUID> = []

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
        .overlay {
            if let focusedClip { actionMenu(for: focusedClip) }
        }
        .overlay {
            if let fullTextClip { fullTextView(for: fullTextClip) }
        }
        .onChange(of: engine.folders) { _, folders in
            if case .folder(let name) = activeFilter, !folders.contains(name) { activeFilter = .all }
        }
        .onChange(of: engine.recentClips) { _, clips in
            // Los menús conservan una copia del elemento: no deben seguir mostrando un secreto
            // que acaba de caducar aunque su tarjeta ya haya desaparecido.
            if let focusedClip, !focusedClip.isSaved, !clips.contains(where: { $0.id == focusedClip.id }) {
                closeMenu()
            }
            if let fullTextClip, !fullTextClip.isSaved, !clips.contains(where: { $0.id == fullTextClip.id }) {
                self.fullTextClip = nil
            }
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
                        sectionHeader("Fijados", symbol: "pin.fill", count: savedClips.count)
                        grid(savedClips)
                    }
                    ForEach(dateSections(recentClips), id: \.title) { section in
                        sectionHeader(section.title, symbol: "clock", count: section.clips.count)
                        grid(section.clips)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }

    /// Agrupa los recientes como un historial: hoy, ayer, esta semana y anteriores.
    private func dateSections(_ clips: [KeyboardClip]) -> [(title: String, clips: [KeyboardClip])] {
        let calendar = Calendar.current
        var order: [String] = []
        var groups: [String: [KeyboardClip]] = [:]
        for clip in clips {
            let title: String
            if calendar.isDateInToday(clip.date) {
                title = "Hoy"
            } else if calendar.isDateInYesterday(clip.date) {
                title = "Ayer"
            } else if (calendar.dateComponents([.day], from: clip.date, to: .now).day ?? 0) < 7 {
                title = "Esta semana"
            } else {
                title = "Anteriores"
            }
            if groups[title] == nil { order.append(title) }
            groups[title, default: []].append(clip)
        }
        return order.map { (title: $0, clips: groups[$0] ?? []) }
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
                    InstantButton { activeFilter = item } label: {
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

    private func sectionHeader(_ title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Label(title, systemImage: symbol)
            Text("· \(count)")
        }
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
                    isSelected: engine.selectedClipIDs.contains(clip.id),
                    isRevealed: revealedIDs.contains(clip.id)
                )
                // Toque y pulsación larga con un reconocedor de UIKit (en iOS 27 los de SwiftUI se
                // retrasan); si el dedo se desplaza, deja desplazar la lista.
                .gesture(
                    InstantTouchGesture(
                        longPressDuration: 0.4,
                        onTap: {
                            if engine.isEditingClips {
                                engine.toggleClipSelection(clip)
                            } else {
                                engine.keyFeedback(.character)
                                engine.useClip(clip)
                            }
                        },
                        onLongPress: {
                            guard !engine.isEditingClips else { return }
                            engine.keyFeedback(.modifier)
                            menuMode = .actions
                            focusedClip = clip
                        }
                    )
                )
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
                InstantButton("Activar portapapeles") { engine.setClipboardEnabled(true) }
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
                Text("Copia algo con el teclado abierto, o usa Compartir › Super Teclado en cualquier app.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.text)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Selección múltiple

    private var editingBar: some View {
        let selected = engine.selectedClips
        let allClips = savedClips + recentClips
        let everythingSelected = !allClips.isEmpty && selected.count == allClips.count
        return HStack(spacing: 4) {
            barButton(everythingSelected ? "Ninguno" : "Todos", symbol: "checklist") {
                engine.selectedClipIDs = everythingSelected ? [] : Set(allClips.map(\.id))
            }
            Spacer(minLength: 0)
            if selected.isEmpty {
                barButton("Borrar recientes", symbol: "clock.badge.xmark", destructive: true) {
                    engine.clearRecents()
                }
                .disabled(engine.recentClips.isEmpty)
            } else {
                barButton("Pegar", symbol: "arrow.down.doc") {
                    engine.pasteClips(selected)
                    finishEditing()
                }
                barButton("Copiar", symbol: "doc.on.doc") {
                    engine.copyClips(selected)
                    finishEditing()
                }
                barButton("Fijar", symbol: "pin") {
                    engine.pinClips(selected)
                    engine.selectedClipIDs = []
                }
                .disabled(!selected.contains { !$0.isSaved })
                barButton("Borrar", symbol: "trash", destructive: true) {
                    engine.deleteClips(selected)
                    engine.selectedClipIDs = []
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(palette.specialKey.opacity(0.6))
    }

    private func finishEditing() {
        engine.selectedClipIDs = []
        engine.isEditingClips = false
    }

    private func barButton(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        InstantButton(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(destructive ? Color.red : palette.text)
            .padding(.horizontal, 8)
            .frame(minWidth: 52, minHeight: 40)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Opciones de un elemento

    private func actionMenu(for clip: KeyboardClip) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .gesture(InstantTouchGesture(onTap: { closeMenu() }))
            VStack(spacing: 10) {
                menuPreview(for: clip)
                switch menuMode {
                case .actions: actionGrid(for: clip)
                case .pasteAs: pasteAsList(for: clip)
                case .folders: folderList(for: clip)
                }
            }
            .padding(12)
            .background(palette.popup, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(8)
        }
        .transition(.opacity)
    }

    private func menuPreview(for clip: KeyboardClip) -> some View {
        HStack(spacing: 6) {
            if menuMode != .actions {
                InstantButton { menuMode = .actions } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
            }
            Group {
                if clip.isImage {
                    Label("Imagen", systemImage: "photo")
                } else if clip.isSensitive && !revealedIDs.contains(clip.id) {
                    Label("Contenido privado", systemImage: "lock.fill")
                } else {
                    Text(clip.text)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(palette.secondaryText)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(clip.text.count) car.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .opacity(clip.isImage ? 0 : 1)
        }
    }

    private func actionGrid(for clip: KeyboardClip) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            menuButton(clip.isSaved ? "Desfijar" : "Fijar", symbol: clip.isSaved ? "pin.slash" : "pin") {
                engine.togglePin(clip)
                closeMenu()
            }
            menuButton(clip.isImage ? "Copiar" : "Pegar", symbol: clip.isImage ? "doc.on.doc" : "arrow.down.doc") {
                engine.useClip(clip)
                closeMenu()
            }
            if !clip.isImage {
                menuButton("Copiar", symbol: "doc.on.doc") {
                    engine.copyClip(clip)
                    closeMenu()
                }
                menuButton("Ver todo", symbol: "text.viewfinder") {
                    fullTextClip = clip
                    closeMenu()
                }
                menuButton("Pegar como", symbol: "textformat") { menuMode = .pasteAs }
            }
            menuButton("Carpeta", symbol: "folder") { menuMode = .folders }
            if clip.isSensitive {
                let revealed = revealedIDs.contains(clip.id)
                menuButton(revealed ? "Ocultar" : "Mostrar", symbol: revealed ? "eye.slash" : "eye") {
                    if revealed { revealedIDs.remove(clip.id) } else { revealedIDs.insert(clip.id) }
                    closeMenu()
                }
            }
            menuButton("Eliminar", symbol: "trash", destructive: true) {
                engine.deleteClips([clip])
                closeMenu()
            }
        }
    }

    private func pasteAsList(for clip: KeyboardClip) -> some View {
        VStack(spacing: 6) {
            ForEach(ClipboardClassifier.Transform.allCases) { transform in
                InstantButton {
                    engine.useClip(clip, transform: transform)
                    closeMenu()
                } label: {
                    HStack {
                        Text(transform.title).font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(transform.apply(to: clip.text).replacingOccurrences(of: "\n", with: " ⏎ "))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .trailing)
                            .opacity(clip.isSensitive ? 0 : 1)
                    }
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func folderList(for clip: KeyboardClip) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                folderRow("Sin carpeta", symbol: "tray", isCurrent: clip.isSaved && clip.folderName == nil) {
                    engine.moveClip(clip, toFolder: nil)
                    closeMenu()
                }
                ForEach(engine.folders, id: \.self) { folder in
                    folderRow(folder, symbol: "folder", isCurrent: clip.folderName == folder) {
                        engine.moveClip(clip, toFolder: folder)
                        closeMenu()
                    }
                }
                if engine.folders.isEmpty {
                    Text("Crea carpetas en la app Super Teclado › Ajustes › Carpetas.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxHeight: 170)
    }

    private func folderRow(_ title: String, symbol: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        InstantButton(action: action) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 14, weight: .medium))
                Spacer()
                if isCurrent { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func closeMenu() {
        focusedClip = nil
        menuMode = .actions
    }

    private func menuButton(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        InstantButton(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(destructive ? Color.red : palette.text)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Texto completo

    private func fullTextView(for clip: KeyboardClip) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(clip.text.count) caracteres")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                InstantButton { fullTextClip = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            ScrollView {
                Text(clip.text)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                fullTextButton("Pegar", symbol: "arrow.down.doc") {
                    engine.useClip(clip)
                    fullTextClip = nil
                }
                fullTextButton("Copiar", symbol: "doc.on.doc") {
                    engine.copyClip(clip)
                    fullTextClip = nil
                }
            }
            .padding(10)
        }
        .background(palette.opaqueBackground)
        .transition(.opacity)
    }

    private func fullTextButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        InstantButton(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ClipTileView: View {
    @Environment(\.keyboardPalette) private var palette
    let clip: KeyboardClip
    let isEditing: Bool
    let isSelected: Bool
    var isRevealed = false

    private var isMasked: Bool { clip.isSensitive && !isRevealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let fileName = clip.imageFileName {
                ClipThumbnailView(fileName: fileName)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if isMasked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("••••••••")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
                Text(clip.isSaved ? "Privado · fijado" : "Privado · temporal")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    if let color = ClipboardClassifier.hexColor(clip.text) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 18, height: 18)
                    }
                    Text(clip.text)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.text)
                        .lineLimit(clip.linkDomain == nil ? 3 : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if let domain = clip.linkDomain {
                    Label(domain, systemImage: "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                }
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

// MARK: Búsqueda

/// Buscador del portapapeles: lo que se escribe con el teclado filtra el historial.
struct ClipboardSearchBarView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            PanelBackButton(title: "") { engine.open(.clipboard) }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryText)
                Text(engine.searchQuery.isEmpty ? "Buscar en el portapapeles" : engine.searchQuery)
                    .foregroundStyle(engine.searchQuery.isEmpty ? palette.secondaryText : palette.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.accent)
                    .frame(width: 2, height: 18)
                Spacer(minLength: 0)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(palette.chip, in: Capsule())
            Text("\(engine.clipSearchResults.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .frame(minWidth: 28)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Resultados de la búsqueda encima del teclado; toca uno para pegarlo.
struct ClipboardSearchResultsView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        Group {
            if engine.clipSearchResults.isEmpty {
                Text(engine.searchQuery.isEmpty ? "El portapapeles está vacío" : "Sin resultados")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(engine.clipSearchResults) { clip in
                            InstantButton {
                                engine.keyFeedback(.character)
                                engine.useClip(clip)
                            } label: {
                                chip(for: clip)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func chip(for clip: KeyboardClip) -> some View {
        HStack(spacing: 6) {
            if let fileName = clip.imageFileName {
                ClipThumbnailView(fileName: fileName)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Imagen")
            } else {
                Image(systemName: clip.isSensitive ? "lock.fill" : (clip.isSaved ? "pin.fill" : "doc.on.clipboard"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.accent)
                Text(clip.isSensitive ? "••••••••" : clip.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(palette.text)
        .padding(.horizontal, 12)
        .frame(maxWidth: 220, minHeight: 38)
        .background(palette.tile, in: Capsule())
    }
}
