import Foundation

/// Base de predicción de la siguiente palabra: pares de palabras frecuentes sacados de frases
/// reales (Tatoeba). Se combina con lo que aprende el teclado de cada usuario.
final class BigramModel: Sendable {
    /// Clave de las palabras con las que suele empezar una frase.
    static let sentenceStartKey = "<s>"

    private let followers: [String: [(word: String, count: Int)]]

    init(followers: [String: [(word: String, count: Int)]]) {
        self.followers = followers
    }

    /// Líneas «palabra⇥siguiente cuenta|siguiente cuenta…».
    static func parse(_ text: String) -> BigramModel {
        var followers: [String: [(word: String, count: Int)]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let next = parts[1].split(separator: "|").compactMap { item -> (word: String, count: Int)? in
                let pieces = item.split(separator: " ")
                guard pieces.count == 2, let count = Int(pieces[1]) else { return nil }
                return (String(pieces[0]), count)
            }
            if !next.isEmpty { followers[String(parts[0])] = next }
        }
        return BigramModel(followers: followers)
    }

    static func load(from url: URL) -> BigramModel? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    func followers(of word: String) -> [(word: String, count: Int)] {
        followers[word.lowercased()] ?? []
    }

    var sentenceStarters: [(word: String, count: Int)] {
        followers[Self.sentenceStartKey] ?? []
    }

    /// Mezcla la base con lo aprendido: lo que escribe el usuario pesa mucho más.
    static func rank(
        base: [(word: String, count: Int)],
        learned: [String: Int],
        limit: Int = 3
    ) -> [String] {
        var scores: [String: Double] = [:]
        let baseTotal = Double(max(base.reduce(0) { $0 + $1.count }, 1))
        for entry in base {
            scores[entry.word, default: 0] += Double(entry.count) / baseTotal
        }
        for (word, count) in learned where count >= 2 {
            scores[word, default: 0] += Double(count)
        }
        return scores
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}

/// Variables de los atajos: «{fecha}», «{hora}», «{dia}» y «{fecha_larga}».
enum ShortcutVariables {
    static func expand(_ text: String, now: Date = .now, locale: Locale = Locale(identifier: "es_ES")) -> String {
        guard text.contains("\u{7B}") else { return text }
        var result = text
        let replacements: [String: String] = [
            "{fecha}": now.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale)),
            "{fecha_larga}": now.formatted(.dateTime.day().month(.wide).year().locale(locale)),
            "{hora}": now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale)),
            "{dia}": now.formatted(.dateTime.weekday(.wide).locale(locale))
        ]
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }
}
