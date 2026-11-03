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
    @AppStorage(KeyboardPreferenceKey.longPressDelay, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var longPressDelay = 330

    @AppStorage(KeyboardPreferenceKey.englishSecondLanguage, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var englishSecondLanguage = false
    @AppStorage(KeyboardPreferenceKey.incognito, store: UserDefaults(suiteName: SharedClipboardStore.appGroupID)) private var incognito = false

    @State private var testText = ""
    @State private var showClearWordsConfirmation = false

    var body: some View {
        Form {
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

            Section("Preferencias") {
                Toggle("Fila de números", isOn: $numberRow)
                Toggle("Mostrar símbolos con pulsación larga", isOn: $longPressSymbols)
                Toggle("Ventana emergente al pulsar teclas", isOn: $keyPopups)
                Toggle("Sonido al pulsar teclas", isOn: $sound)
                Toggle("Vibración al pulsar teclas", isOn: $haptics)
                Picker("Modo una mano", selection: $oneHandedMode) {
                    ForEach(OneHandedMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Picker("Altura del teclado", selection: $height) {
                    ForEach(KeyboardHeightOption.allCases) { option in Text(option.title).tag(option) }
                }
                Picker("Retraso de la pulsación larga", selection: $longPressDelay) {
                    Text("Corto").tag(220)
                    Text("Normal").tag(330)
                    Text("Largo").tag(500)
                }
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
                LabeledContent("Idioma principal", value: "Español")
                Toggle("Inglés como segundo idioma", isOn: $englishSecondLanguage)
            } header: {
                Text("Idiomas")
            } footer: {
                Text("Con el inglés activado, el teclado sugiere, corrige y reconoce trazos en los dos idiomas a la vez.")
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
