import SwiftUI

/// Palabras que el teclado no debe corregir y atajos que se expanden al escribirlos.
struct PersonalDictionaryView: View {
    @State private var words: [String] = []
    @State private var shortcuts: [(shortcut: String, phrase: String)] = []
    @State private var newWord = ""
    @State private var newShortcut = ""
    @State private var newPhrase = ""
    @State private var searchText = ""

    private var filteredWords: [String] {
        searchText.isEmpty ? words : words.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Form {
            Section {
                TextField("Atajo (por ejemplo, qtal)", text: $newShortcut)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Texto completo", text: $newPhrase, axis: .vertical)
                Button("Añadir atajo", action: addShortcut)
                    .disabled(
                        newShortcut.trimmingCharacters(in: .whitespaces).isEmpty
                            || newPhrase.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                ForEach(shortcuts, id: \.shortcut) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.shortcut).font(.headline)
                        Text(item.phrase).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .onDelete(perform: deleteShortcuts)
            } header: {
                Text("Atajos")
            } footer: {
                Text("Al escribir un atajo, el texto completo aparece en el centro de la barra y se inserta al pulsar espacio. Puedes usar {fecha}, {fecha_larga}, {hora} y {dia} para insertar la fecha o la hora del momento.")
            }

            Section {
                HStack {
                    TextField("Añadir palabra", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(action: addWord) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Añadir palabra")
                }
                if words.isEmpty {
                    Text("El teclado aprende las palabras que escribes a menudo.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredWords, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete(perform: deleteWords)
                }
            } header: {
                Text("Palabras aprendidas")
            } footer: {
                Text("Desliza una palabra para eliminarla y que el teclado vuelva a corregirla.")
            }
        }
        .navigationTitle("Diccionario personal")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Buscar palabras")
        .onAppear(perform: reload)
    }

    private func reload() {
        words = PersonalDictionary.learnedWords()
            .filter { $0.value >= PersonalDictionary.knownThreshold }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
        shortcuts = PersonalDictionary.shortcuts()
            .sorted { $0.key < $1.key }
            .map { (shortcut: $0.key, phrase: $0.value) }
    }

    private func addWord() {
        PersonalDictionary.addWord(newWord)
        newWord = ""
        reload()
    }

    private func deleteWords(at offsets: IndexSet) {
        let visible = filteredWords
        offsets.map { visible[$0] }.forEach(PersonalDictionary.removeWord)
        reload()
    }

    private func addShortcut() {
        guard PersonalDictionary.setShortcut(newShortcut, phrase: newPhrase) else { return }
        newShortcut = ""
        newPhrase = ""
        reload()
    }

    private func deleteShortcuts(at offsets: IndexSet) {
        offsets.map { shortcuts[$0].shortcut }.forEach(PersonalDictionary.removeShortcut)
        reload()
    }
}
