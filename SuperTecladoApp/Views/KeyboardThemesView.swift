import PhotosUI
import SwiftUI

/// Selector de temas con vista previa, como la sección «Tema» de Gboard.
struct KeyboardThemesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(KeyboardPreferenceKey.theme, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID))
    private var theme: KeyboardThemeOption = .system
    @AppStorage(KeyboardPreferenceKey.keyBorders, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID))
    private var keyBorders = true
    @AppStorage(KeyboardPreferenceKey.backgroundDim, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID))
    private var backgroundDim = 0.35

    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isSavingPhoto = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 14)]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(KeyboardThemeOption.allCases.filter { $0 != .photo }) { option in
                        themeButton(option)
                    }
                    if photo != nil { themeButton(.photo) }
                }
                .padding(.vertical, 8)
                Toggle("Bordes de las teclas", isOn: $keyBorders)
            } header: {
                Text("Temas")
            } footer: {
                Text("«Automático» sigue el modo claro u oscuro del sistema y de cada app. También puedes cambiar de tema desde la paleta de la barra del teclado.")
            }

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photo == nil ? "Elegir una foto" : "Cambiar foto", systemImage: "photo.on.rectangle")
                }
                if isSavingPhoto {
                    ProgressView()
                }
                if photo != nil {
                    VStack(alignment: .leading) {
                        Text("Oscurecer la foto")
                        Slider(value: $backgroundDim, in: 0...0.7)
                    }
                    Button("Quitar foto", role: .destructive, action: removePhoto)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            } header: {
                Text("Mi foto")
            } footer: {
                Text("Usa una foto propia como fondo del teclado. Oscurecerla ayuda a leer las teclas.")
            }
        }
        .navigationTitle("Temas")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { photo = KeyboardBackgroundStore.load(maxPixelSize: 600) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await savePhoto(item) }
        }
    }

    private func themeButton(_ option: KeyboardThemeOption) -> some View {
        Button { theme = option } label: {
            VStack(spacing: 6) {
                ThemePreview(option: option, systemIsDark: colorScheme == .dark, photo: photo, dim: backgroundDim)
                    .frame(height: 74)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme == option ? Color.cyan : Color.secondary.opacity(0.25), lineWidth: theme == option ? 3 : 1)
                    }
                Text(option.title)
                    .font(.caption)
                    .foregroundStyle(theme == option ? Color.cyan : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(theme == option ? .isSelected : [])
    }

    private func savePhoto(_ item: PhotosPickerItem) async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              KeyboardBackgroundStore.save(imageData: data) else {
            errorMessage = "No se pudo usar esa foto."
            return
        }
        errorMessage = nil
        photo = KeyboardBackgroundStore.load(maxPixelSize: 600)
        theme = .photo
    }

    private func removePhoto() {
        KeyboardBackgroundStore.remove()
        photo = nil
        photoItem = nil
        if theme == .photo { theme = .system }
    }
}

/// Miniatura de un teclado con los colores del tema.
private struct ThemePreview: View {
    let option: KeyboardThemeOption
    let systemIsDark: Bool
    let photo: UIImage?
    let dim: Double

    var body: some View {
        let palette = KeyboardPalette.make(theme: option, systemIsDark: systemIsDark)
        ZStack {
            if option == .photo, let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(dim))
            } else {
                palette.background
            }
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<(row == 2 ? 5 : 6), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2).fill(palette.key)
                        }
                    }
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.specialKey).frame(width: 14)
                    RoundedRectangle(cornerRadius: 2).fill(palette.key)
                    RoundedRectangle(cornerRadius: 2).fill(palette.accent).frame(width: 14)
                }
            }
            .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
