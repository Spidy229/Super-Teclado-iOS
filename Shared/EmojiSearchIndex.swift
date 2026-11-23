import Foundation

/// Búsqueda de emojis por nombre y palabras clave en español (datos CLDR de Unicode).
final class EmojiSearchIndex: Sendable {
    private struct Entry: Sendable {
        let name: String
        let keywords: [String]
        let nameTokens: [String]
        let tokens: [String]
    }

    private let entries: [String: Entry]

    private init(entries: [String: Entry]) {
        self.entries = entries
    }

    /// Líneas con el formato «emoji⇥nombre⇥palabra|palabra…».
    static func parse(_ text: String) -> EmojiSearchIndex {
        var entries: [String: Entry] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let key = key(for: String(parts[0]))
            let name = normalize(String(parts[1]))
            let keywords = parts.count > 2
                ? parts[2].split(separator: "|").map { normalize(String($0)) }
                : []
            let nameTokens = tokenize(name)
            entries[key] = Entry(
                name: name,
                keywords: keywords,
                nameTokens: nameTokens,
                tokens: nameTokens + keywords.flatMap(tokenize)
            )
        }
        return EmojiSearchIndex(entries: entries)
    }

    static func load(from url: URL) -> EmojiSearchIndex? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Emojis de `emojis` que coinciden con la búsqueda, conservando su orden en caso de empate.
    func search(_ query: String, in emojis: [String], limit: Int = 60) -> [String] {
        let normalized = Self.normalize(query)
        let words = Self.tokenize(normalized)
        guard !words.isEmpty else { return [] }

        var scored: [(emoji: String, score: Int, order: Int)] = []
        var seen = Set<String>()
        for (order, emoji) in emojis.enumerated() {
            let key = Self.key(for: emoji)
            guard !seen.contains(key), let entry = entries[key],
                  let score = score(entry, query: normalized, words: words) else { continue }
            seen.insert(key)
            scored.append((emoji, score, order))
        }
        return scored
            .sorted { $0.score == $1.score ? $0.order < $1.order : $0.score < $1.score }
            .prefix(limit)
            .map(\.emoji)
    }

    func name(for emoji: String) -> String? {
        entries[Self.key(for: emoji)]?.name
    }

    private func score(_ entry: Entry, query: String, words: [String]) -> Int? {
        if entry.name == query { return 0 }
        if entry.keywords.contains(query) { return 1 }
        let allWordsMatch = words.allSatisfy { word in entry.tokens.contains { $0.hasPrefix(word) } }
        guard allWordsMatch else { return nil }
        if let first = words.first, entry.nameTokens.first?.hasPrefix(first) == true { return 2 }
        if let first = words.first, entry.nameTokens.contains(where: { $0.hasPrefix(first) }) { return 3 }
        return 4
    }

    /// Clave sin selectores de variación (U+FE0F), para que «❤️» y «❤» coincidan.
    static func key(for emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0.value != 0xFE0F }))
    }

    private static func normalize(_ text: String) -> String {
        WordDictionary.fold(text.lowercased()).trimmingCharacters(in: .whitespaces)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
