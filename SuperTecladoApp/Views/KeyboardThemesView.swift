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
    @AppStorage(KeyboardPreferenceKey.glassTransparency, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID))
    private var glassTransparency = 1.0

    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isSavingPhoto = false
    @State private var errorMessage: String?
    @State private var customColors = CustomThemeColors.load()

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 14)]

    var body: some View {
        // La etiqueta de PhotosPicker es un cierre Sendable: no puede leer el estado de la vista.
        let pickerTitle = photo == nil ? "Elegir una foto" : "Cambiar foto"
        Form {
            KeyboardSettingsTransferSection()

            Section {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(KeyboardThemeOption.allCases.filter { $0 != .photo }) { option in
                        themeButton(option)
                    }
                    if photo != nil { themeButton(.photo) }
                }
                .padding(.vertical, 8)
                if theme == .glass {
                    VStack(alignment: .leading) {
                        LabeledContent("Transparencia del cristal") {
                            Text("\(Int((glassTransparency * 100).rounded())) %")
                                .monospacedDigit()
                        }
                        Slider(value: $glassTransparency, in: 0...1, step: 0.05)
                            .accessibilityLabel("Transparencia del cristal")
                    }
                }
                Toggle("Bordes de las teclas", isOn: $keyBorders)
            } header: {
                Text("Temas")
            } footer: {
                Text("«Automático» y «Cristal» siguen el modo claro u oscuro del sistema. «Cristal» deja ver el fondo translúcido de iOS; su transparencia se ajusta aquí o en la paleta del teclado (100 % es el cristal más transparente). También puedes cambiar de tema desde la paleta de la barra del teclado.")
            }

            Section {
                ColorPicker("Fondo", selection: colorBinding(\.background), supportsOpacity: false)
                ColorPicker("Teclas", selection: colorBinding(\.key), supportsOpacity: false)
                ColorPicker("Letras", selection: colorBinding(\.text), supportsOpacity: false)
                ColorPicker("Acento (intro y selección)", selection: colorBinding(\.accent), supportsOpacity: false)
                Toggle("Fondo degradado", isOn: Binding(
                    get: { customColors.backgroundEnd != nil },
                    set: { enabled in
                        customColors.backgroundEnd = enabled
                            ? RGBColor(
                                red: min(customColors.background.red + 0.25, 1),
                                green: customColors.background.green,
                                blue: min(customColors.background.blue + 0.3, 1)
                            )
                            : nil
                        customColors.save()
                        theme = .custom
                    }
                ))
                if customColors.backgroundEnd != nil {
                    ColorPicker("Segundo color del fondo", selection: endColorBinding, supportsOpacity: false)
                }
                Button("Restablecer colores") {
                    customColors = CustomThemeColors()
                    customColors.save()
                }
            } header: {
                Text("Tema personalizado")
            } footer: {
                Text("Al cambiar un color se activa el tema «Personalizado». Las teclas especiales usan un tono más suave del color de las teclas.")
            }

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(pickerTitle, systemImage: "photo.on.rectangle")
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

    private func colorBinding(_ keyPath: WritableKeyPath<CustomThemeColors, RGBColor>) -> Binding<Color> {
        Binding(
            get: { KeyboardPalette.color(customColors[keyPath: keyPath]) },
            set: { newValue in
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                UIColor(newValue).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                customColors[keyPath: keyPath] = RGBColor(red: Double(red), green: Double(green), blue: Double(blue))
                customColors.save()
                theme = .custom
            }
        )
    }

    private var endColorBinding: Binding<Color> {
        Binding(
            get: { KeyboardPalette.color(customColors.backgroundEnd ?? customColors.background) },
            set: { newValue in
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                UIColor(newValue).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                customColors.backgroundEnd = RGBColor(red: Double(red), green: Double(green), blue: Double(blue))
                customColors.save()
                theme = .custom
            }
        )
    }

    private func themeButton(_ option: KeyboardThemeOption) -> some View {
        Button { theme = option } label: {
            VStack(spacing: 6) {
                KeyboardThemePreview(
                    option: option,
                    systemIsDark: colorScheme == .dark,
                    custom: customColors,
                    photo: photo,
                    dim: backgroundDim,
                    glassTransparency: glassTransparency
                )
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
