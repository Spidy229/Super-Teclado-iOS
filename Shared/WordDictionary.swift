import Foundation

/// Diccionario de palabras ordenado por frecuencia de uso. Es inmutable para poder cargarlo
/// en segundo plano y compartirlo entre hilos.
final class WordDictionary: Sendable {
    /// Palabras de más a menos frecuentes. Los índices se guardan como `Int32` para que el
    /// diccionario ocupe la mitad de memoria (los teclados de iOS tienen un límite estricto).
    let words: [String]
    private let counts: [Int32]
    private let indexByWord: [String: Int32]
    /// Solo para palabras con tildes, «ñ» o «ç»: forma sin tildes → palabra más usada.
    private let bestIndexByFolded: [String: Int32]
    private let indicesByFirstLetter: [Character: [Int32]]
    /// Índices agrupados por la primera y la última tecla, para la escritura deslizando.
    private let indicesByGlideEnds: [String: [Int32]]

    init(entries: [(word: String, count: Int)]) {
        var words: [String] = []
        var counts: [Int32] = []
        var indexByWord: [String: Int32] = [:]
        var bestIndexByFolded: [String: Int32] = [:]
        var indicesByFirstLetter: [Character: [Int32]] = [:]
        var indicesByGlideEnds: [String: [Int32]] = [:]
        words.reserveCapacity(entries.count)
        counts.reserveCapacity(entries.count)
        indexByWord.reserveCapacity(entries.count)

        for entry in entries.sorted(by: { $0.count > $1.count }) {
            let word = entry.word.lowercased()
            guard !word.isEmpty, indexByWord[word] == nil else { continue }
            let index = Int32(words.count)
            let folded = Self.fold(word)
            words.append(word)
            counts.append(Int32(clamping: max(entry.count, 1)))
            indexByWord[word] = index
            // Como van de más a menos usadas, si la forma sin tilde ya está, es más frecuente.
            if folded != word, bestIndexByFolded[folded] == nil, indexByWord[folded] == nil {
                bestIndexByFolded[folded] = index
            }
            if let first = folded.first { indicesByFirstLetter[first, default: []].append(index) }
            let keys = Self.keyLetters(word)
            if keys.count >= 2, let first = keys.first, let last = keys.last {
                indicesByGlideEnds[String([first, last]), default: []].append(index)
            }
        }

        self.words = words
        self.counts = counts
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
    static let secondaryLimit = 20_000

    static func load(from url: URL, secondary: URL?, secondaryWeight: Double) -> WordDictionary? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var combined = entries(from: text)
        if let secondary, let secondaryText = try? String(contentsOf: secondary, encoding: .utf8) {
            // El segundo idioma se limita a sus palabras más usadas para ahorrar memoria.
            combined += entries(from: secondaryText, weight: secondaryWeight).prefix(secondaryLimit)
        }
        return WordDictionary(entries: combined)
    }

    var isEmpty: Bool { words.isEmpty }

    func contains(_ word: String) -> Bool {
        indexByWord[word.lowercased()] != nil
    }

    func count(of word: String) -> Int? {
        indexByWord[word.lowercased()].map { Int(counts[Int($0)]) }
    }

    func word(at index: Int32) -> String { words[Int(index)] }

    func count(at index: Int32) -> Int { Int(counts[Int(index)]) }

    /// Forma más usada que coincide sin tildes: «tambien» → «también», «manana» → «mañana».
    func bestForm(matching word: String) -> String? {
        let folded = Self.fold(word.lowercased())
        if let index = bestIndexByFolded[folded] { return words[Int(index)] }
        return indexByWord[folded] == nil ? nil : folded
    }

    /// Palabras que empiezan por el prefijo (sin distinguir tildes), de más a menos usadas.
    func completions(for prefix: String, limit: Int) -> [String] {
        let foldedPrefix = Self.fold(prefix.lowercased())
        guard let first = foldedPrefix.first, let candidates = indicesByFirstLetter[first] else { return [] }
        var result: [String] = []
        for index in candidates {
            let candidate = words[Int(index)]
            guard candidate.count > foldedPrefix.count else { continue }
            // Solo se quitan tildes cuando hace falta, para no crear cadenas en cada pulsación.
            let matches = candidate.hasPrefix(foldedPrefix)
                || (!candidate.allSatisfy(\.isASCII) && Self.fold(candidate).hasPrefix(foldedPrefix))
            guard matches else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    func glideCandidates(first: Character, last: Character) -> [Int32] {
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
