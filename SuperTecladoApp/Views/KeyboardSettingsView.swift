import AudioToolbox
import SwiftUI
import UIKit

struct KeyboardSettingsView: View {
    @AppStorage(KeyboardPreferenceKey.theme, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var theme: KeyboardThemeOption = .system
    @AppStorage(KeyboardPreferenceKey.sound, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var sound = false
    @AppStorage(KeyboardPreferenceKey.haptics, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var haptics = true
    @AppStorage(KeyboardPreferenceKey.autocorrect, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var autocorrect = true
    @AppStorage(KeyboardPreferenceKey.autocapitalize, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var autocapitalize = true
    @AppStorage(KeyboardPreferenceKey.doubleSpacePeriod, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var doubleSpacePeriod = true
    @AppStorage(KeyboardPreferenceKey.suggestions, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var suggestions = true
    @AppStorage(KeyboardPreferenceKey.numberRow, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var numberRow = false
    @AppStorage(KeyboardPreferenceKey.keyPopups, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var keyPopups = true
    @AppStorage(KeyboardPreferenceKey.longPressSymbols, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var longPressSymbols = true
    @AppStorage(KeyboardPreferenceKey.quickPaste, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var quickPaste = true
    @AppStorage(KeyboardPreferenceKey.oneHandedMode, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var oneHandedMode: OneHandedMode = .off
    @AppStorage(SharedClipboardStore.automaticCaptureKey, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var clipboardEnabled = true

    @AppStorage(KeyboardPreferenceKey.glideTyping, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var glideTyping = true
    @AppStorage(KeyboardPreferenceKey.glideTrail, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var glideTrail = true
    @AppStorage(KeyboardPreferenceKey.nextWordPrediction, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var nextWordPrediction = true
    @AppStorage(KeyboardPreferenceKey.emojiSuggestions, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var emojiSuggestions = true
    @AppStorage(KeyboardPreferenceKey.height, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var height: KeyboardHeightOption = .normal
    @AppStorage(KeyboardPreferenceKey.longPressDelay, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var longPressDelay = 400

    @AppStorage(KeyboardPreferenceKey.primaryLanguage, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var primaryLanguage: KeyboardLanguage = .spanish
    /// Código del segundo idioma o cadena vacía.
    @AppStorage(KeyboardPreferenceKey.secondaryLanguage, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var secondaryLanguageCode = ""
    /// Distribución elegida o «auto».
    @AppStorage(KeyboardPreferenceKey.layout, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var layoutCode = "auto"
    @AppStorage(KeyboardPreferenceKey.incognito, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var incognito = false
    @AppStorage(KeyboardPreferenceKey.smartTouch, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var smartTouch = true
    @AppStorage(KeyboardPreferenceKey.spaceAfterSuggestion, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var spaceAfterSuggestion = true

    @AppStorage(KeyboardPreferenceKey.hapticsStrength, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var hapticsStrength = 0.6
    @AppStorage(KeyboardPreferenceKey.hapticsStyle, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var hapticsStyle: HapticStyleOption = .light
    @AppStorage(KeyboardPreferenceKey.keyLabelSize, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var keyLabelSize: KeyLabelSize = .normal

    @AppStorage(KeyboardPreferenceKey.soundStyle, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var soundStyle: KeySoundStyle = .modern
    @AppStorage(KeyboardPreferenceKey.favoritesRow, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var favoritesRow = false
    @AppStorage(KeyboardPreferenceKey.favorites, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var favorites = KeyboardPreferences.defaultFavorites

    @State private var testText = ""
    @State private var showClearWordsConfirmation = false

    var body: some View {
        Form {
            Section {
                KeyboardStatusView()
            }

            KeyboardSettingsTransferSection()

            Section {
                setupStep(1, "Abre Ajustes › Super Teclado › Teclados.")
                setupStep(2, "Activa «Super Teclado» y «Permitir acceso total».")
                setupStep(3, "En cualquier app, mantén pulsado 🌐 y elige Super Teclado.")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Abrir Ajustes", systemImage: "gear")
                }
            } header: {
                Text("Activar el teclado")
            } footer: {
                Text("El acceso total es necesario para el portapapeles, la vibración y guardar lo que copias. Nada sale de tu dispositivo.")
            }

            Section("Probar") {
                TextField("Escribe aquí para probar el teclado", text: $testText, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section {
                Toggle("Fila de números", isOn: $numberRow)
                Toggle("Mostrar símbolos con pulsación larga", isOn: $longPressSymbols)
                Toggle("Ventana emergente al pulsar teclas", isOn: $keyPopups)
                Picker("Tamaño de las letras", selection: $keyLabelSize) {
                    ForEach(KeyLabelSize.allCases) { size in Text(size.title).tag(size) }
                }
                Picker("Modo una mano", selection: $oneHandedMode) {
                    ForEach(OneHandedMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Picker("Altura del teclado", selection: $height) {
                    ForEach(KeyboardHeightOption.allCases) { option in Text(option.title).tag(option) }
                }
                Picker("Retraso de la pulsación larga", selection: $longPressDelay) {
                    Text("Corto").tag(250)
                    Text("Normal").tag(400)
                    Text("Largo").tag(550)
                }
                Toggle("Precisión inteligente", isOn: $smartTouch)
                Toggle("Espacio tras elegir una sugerencia", isOn: $spaceAfterSuggestion)
            } header: {
                Text("Preferencias")
            } footer: {
                Text("Con «Precisión inteligente», si tocas justo entre dos letras el teclado elige la que forma una palabra, como el teclado de Apple. Un toque claro sobre una tecla siempre escribe esa tecla.")
            }

            Section {
                Toggle("Sonido al pulsar teclas", isOn: $sound)
                if sound {
                    Picker("Tipo de sonido", selection: $soundStyle) {
                        ForEach(KeySoundStyle.allCases) { style in Text(style.title).tag(style) }
                    }
                    Button(action: testSound) {
                        Label("Probar sonido", systemImage: "speaker.wave.2")
                    }
                }
            } header: {
                Text("Sonido")
            } footer: {
                Text("El volumen sigue al de los sonidos del sistema y no suena con el modo silencio.")
            }

            Section {
                Toggle("Fila de favoritos", isOn: $favoritesRow)
                if favoritesRow {
                    TextField("Emojis y símbolos", text: $favorites, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.title3)
                    Button("Restablecer favoritos") { favorites = KeyboardPreferences.defaultFavorites }
                }
            } header: {
                Text("Favoritos")
            } footer: {
                Text("Una fila encima de las teclas con tus emojis y símbolos más usados. Escríbelos o pégalos seguidos; si la dejas vacía, muestra tus emojis recientes.")
            }

            Section {
                Toggle("Vibración al pulsar teclas", isOn: $haptics)
                if haptics {
                    Picker("Tipo de vibración", selection: $hapticsStyle) {
                        ForEach(HapticStyleOption.allCases) { style in Text(style.title).tag(style) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Intensidad")
                            Spacer()
                            Text("\(Int((hapticsStrength * 100).rounded())) %")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $hapticsStrength, in: 0.1...1, step: 0.05) {
                            Text("Intensidad")
                        } minimumValueLabel: {
                            Image(systemName: "iphone.radiowaves.left.and.right").imageScale(.small)
                        } maximumValueLabel: {
                            Image(systemName: "iphone.radiowaves.left.and.right").imageScale(.large)
                        } onEditingChanged: { editing in
                            if !editing { testHaptic() }
                        }
                    }
                    Button(action: testHaptic) {
                        Label("Probar vibración", systemImage: "hand.tap")
                    }
                }
            } header: {
                Text("Vibración")
            } footer: {
                Text("El teclado necesita «Permitir acceso total» para vibrar. Las teclas especiales (borrar, mayúsculas, intro) vibran un poco más fuerte.")
            }

            Section {
                Toggle("Escritura deslizando", isOn: $glideTyping)
                Toggle("Mostrar el trazo", isOn: $glideTrail)
                    .disabled(!glideTyping)
            } header: {
                Text("Escritura deslizando")
            } footer: {
                Text("Desliza el dedo de letra en letra sin levantarlo para escribir una palabra. Si no es la que querías, elige otra en la barra o pulsa borrar para quitarla entera.")
            }

            Section {
                NavigationLink {
                    KeyboardThemesView()
                } label: {
                    LabeledContent {
                        Text(theme.title)
                    } label: {
                        Label("Tema", systemImage: "paintpalette")
                    }
                }
            }

            Section {
                Picker("Idioma principal", selection: $primaryLanguage) {
                    ForEach(KeyboardLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Picker("Segundo idioma", selection: $secondaryLanguageCode) {
                    Text("Ninguno").tag("")
                    ForEach(KeyboardLanguage.allCases.filter { $0 != primaryLanguage }) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                Picker("Distribución", selection: $layoutCode) {
                    Text("Automática (\(primaryLanguage.defaultLayout.title))").tag("auto")
                    ForEach(LetterLayout.allCases) { layout in Text(layout.title).tag(layout.rawValue) }
                }
            } header: {
                Text("Idiomas")
            } footer: {
                Text("Con dos idiomas, el teclado sugiere, corrige y reconoce trazos en ambos a la vez. Los acentos y letras de cada idioma (ñ, ç, ß…) están en la pulsación larga.")
            }

            Section {
                Toggle("Modo incógnito", isOn: $incognito)
            } footer: {
                Text("En incógnito el teclado no aprende palabras ni guarda lo que copias. Se activa solo en campos de contraseñas, códigos y tarjetas. También puedes cambiarlo con el icono del ojo en la barra del teclado.")
            }

            Section {
                Toggle("Mostrar sugerencias", isOn: $suggestions)
                Toggle("Autocorrección", isOn: $autocorrect)
                    .disabled(!suggestions)
                Toggle("Mayúsculas automáticas", isOn: $autocapitalize)
                Toggle("Punto con doble espacio", isOn: $doubleSpacePeriod)
                Toggle("Predecir la siguiente palabra", isOn: $nextWordPrediction)
                    .disabled(!suggestions)
                Toggle("Sugerencias de emojis", isOn: $emojiSuggestions)
                    .disabled(!suggestions)
                NavigationLink {
                    PersonalDictionaryView()
                } label: {
                    Label("Diccionario personal", systemImage: "character.book.closed")
                }
                Button("Borrar palabras aprendidas", role: .destructive) {
                    showClearWordsConfirmation = true
                }
            } header: {
                Text("Corrección de texto")
            } footer: {
                Text("Pulsa borrar justo después de una corrección para deshacerla; el teclado recordará tu palabra.")
            }

            Section {
                Toggle("Portapapeles", isOn: $clipboardEnabled)
                Toggle("Sugerir pegar lo último copiado", isOn: $quickPaste)
                    .disabled(!clipboardEnabled)
            } header: {
                Text("Portapapeles")
            } footer: {
                Text("Lo copiado aparece en Recientes durante el tiempo configurado en Ajustes. Mantén pulsado un elemento en el teclado para fijarlo, copiarlo o eliminarlo, o usa el lápiz para editar varios a la vez.")
            }

            Section("Gestos") {
                gestureRow("arrow.left.and.right", "Desliza sobre la barra espaciadora para mover el cursor.")
                gestureRow("delete.left", "Mantén borrar para repetir o desliza a la izquierda para borrar palabras.")
                gestureRow("hand.tap", "Mantén una tecla para ver acentos y símbolos.")
                gestureRow("scribble", "Desliza de letra en letra para escribir sin levantar el dedo.")
                gestureRow("shift", "Toca dos veces mayúsculas para bloquearlas.")
            }
        }
        .navigationTitle("Teclado")
        .onChange(of: primaryLanguage) { _, language in
            if secondaryLanguageCode == language.rawValue { secondaryLanguageCode = "" }
        }
        .onAppear(perform: migrateSecondLanguage)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "¿Borrar las palabras aprendidas?",
            isPresented: $showClearWordsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) { KeyboardPreferences.clearLearnedWords() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    /// La versión 2.2 guardaba «inglés como segundo idioma» como un interruptor.
    private func migrateSecondLanguage() {
        let defaults = SharedClipboardStore.sharedDefaults
        guard defaults?.object(forKey: KeyboardPreferenceKey.secondaryLanguage) == nil,
              defaults?.bool(forKey: KeyboardPreferenceKey.englishSecondLanguage) == true else { return }
        secondaryLanguageCode = KeyboardLanguage.english.rawValue
    }

    private func testSound() {
        AudioServicesPlaySystemSound(SystemSoundID(soundStyle.soundID(isDelete: false, isModifier: false)))
    }

    private func testHaptic() {
        let generator = UIImpactFeedbackGenerator(style: hapticsStyle.feedbackStyle)
        generator.prepare()
        generator.impactOccurred(intensity: hapticsStrength)
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.cyan, in: Circle())
            Text(text)
        }
    }

    private func gestureRow(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.cyan)
        }
    }
}
