import Foundation

/// Diccionario de palabras ordenado por frecuencia de uso. Es inmutable para poder cargarlo
/// en segundo plano y compartirlo entre hilos.
final class WordDictionary: Sendable {
    let words: [String]
    let counts: [Int]
    /// Forma sin tildes ni «ñ» de cada palabra (para completar y corregir tildes).
    private let foldedWords: [String]
    private let indexByWord: [String: Int]
    private let bestIndexByFolded: [String: Int]
    private let indicesByFirstLetter: [Character: [Int]]
    /// Índices agrupados por la primera y la última tecla, para la escritura deslizando.
    private let indicesByGlideEnds: [String: [Int]]

    init(entries: [(word: String, count: Int)]) {
        var words: [String] = []
        var counts: [Int] = []
        var foldedWords: [String] = []
        var indexByWord: [String: Int] = [:]
        var bestIndexByFolded: [String: Int] = [:]
        var indicesByFirstLetter: [Character: [Int]] = [:]
        var indicesByGlideEnds: [String: [Int]] = [:]

        for entry in entries.sorted(by: { $0.count > $1.count }) {
            let word = entry.word.lowercased()
            guard !word.isEmpty, indexByWord[word] == nil else { continue }
            let index = words.count
            let folded = Self.fold(word)
            words.append(word)
            counts.append(max(entry.count, 1))
            foldedWords.append(folded)
            indexByWord[word] = index
            if bestIndexByFolded[folded] == nil { bestIndexByFolded[folded] = index }
            if let first = folded.first { indicesByFirstLetter[first, default: []].append(index) }
            let keys = Self.keyLetters(word)
            if keys.count >= 2, let first = keys.first, let last = keys.last {
                indicesByGlideEnds[String([first, last]), default: []].append(index)
            }
        }

        self.words = words
        self.counts = counts
        self.foldedWords = foldedWords
        self.indexByWord = indexByWord
        self.bestIndexByFolded = bestIndexByFolded
        self.indicesByFirstLetter = indicesByFirstLetter
        self.indicesByGlideEnds = indicesByGlideEnds
    }

    /// Lee líneas con el formato «palabra frecuencia».
    static func parse(_ text: String) -> WordDictionary {
        WordDictionary(entries: entries(from: text))
    }

    static func entries(from text: String, weight: Double = 1) -> [(word: String, count: Int)] {
        var entries: [(word: String, count: Int)] = []
        entries.reserveCapacity(40_000)
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let word = parts.first else { continue }
            let count = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            entries.append((String(word), max(1, Int(Double(count) * weight))))
        }
        return entries
    }

    static func load(from url: URL) -> WordDictionary? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Combina el diccionario principal con un segundo idioma. Las frecuencias del segundo se
    /// reducen para que, ante la duda, gane el idioma principal.
    static func load(from url: URL, secondary: URL?, secondaryWeight: Double) -> WordDictionary? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var combined = entries(from: text)
        if let secondary, let secondaryText = try? String(contentsOf: secondary, encoding: .utf8) {
            combined += entries(from: secondaryText, weight: secondaryWeight)
        }
        return WordDictionary(entries: combined)
    }

    var isEmpty: Bool { words.isEmpty }

    func contains(_ word: String) -> Bool {
        indexByWord[word.lowercased()] != nil
    }

    func count(of word: String) -> Int? {
        indexByWord[word.lowercased()].map { counts[$0] }
    }

    /// Forma más usada que coincide sin tildes: «tambien» → «también», «manana» → «mañana».
    func bestForm(matching word: String) -> String? {
        bestIndexByFolded[Self.fold(word.lowercased())].map { words[$0] }
    }

    /// Palabras que empiezan por el prefijo (sin distinguir tildes), de más a menos usadas.
    func completions(for prefix: String, limit: Int) -> [String] {
        let foldedPrefix = Self.fold(prefix.lowercased())
        guard let first = foldedPrefix.first, let candidates = indicesByFirstLetter[first] else { return [] }
        var result: [String] = []
        for index in candidates where foldedWords[index].count > foldedPrefix.count {
            guard foldedWords[index].hasPrefix(foldedPrefix) else { continue }
            result.append(words[index])
            if result.count == limit { break }
        }
        return result
    }

    func glideCandidates(first: Character, last: Character) -> [Int] {
        indicesByGlideEnds[String([first, last])] ?? []
    }

    // MARK: Normalización

    /// Quita tildes, diéresis, la tilde de la «ñ» y la cedilla.
    static func fold(_ text: String) -> String {
        String(text.map { character -> Character in
            switch character {
            case "á", "à", "ä", "â", "ã", "å": "a"
            case "é", "è", "ë", "ê": "e"
            case "í", "ì", "ï", "î": "i"
            case "ó", "ò", "ö", "ô", "õ": "o"
            case "ú", "ù", "ü", "û": "u"
            case "ñ": "n"
            case "ç": "c"
            case "ÿ": "y"
            default: character
            }
        })
    }

    /// Teclas que hay que recorrer para escribir la palabra (la «ñ» y la «ç» tienen tecla propia
    /// en las distribuciones que las incluyen).
    static func keyLetters(_ word: String) -> [Character] {
        word.lowercased().map { character -> Character in
            switch character {
            case "á", "à", "ä", "â", "ã", "å": "a"
            case "é", "è", "ë", "ê": "e"
            case "í", "ì", "ï", "î": "i"
            case "ó", "ò", "ö", "ô", "õ": "o"
            case "ú", "ù", "ü", "û": "u"
            case "ÿ": "y"
            default: character
            }
        }
    }
}
