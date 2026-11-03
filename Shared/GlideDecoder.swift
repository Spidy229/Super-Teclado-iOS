import Foundation

/// Corrección de erratas por distancia de edición 1, dando más peso a las teclas vecinas.
enum TypoCorrector {
    struct Candidate: Equatable {
        let word: String
        let score: Double
    }

    static func candidates(
        for typed: String,
        in dictionary: WordDictionary,
        layout: LetterLayout = .spanish,
        limit: Int = 3
    ) -> [Candidate] {
        let positions = layout.unitPositions
        let alphabet = layout.alphabet
        let letters = WordDictionary.keyLetters(typed).map { letter in
            positions[letter] == nil ? LetterLayout.fallbackKey(for: letter) ?? letter : letter
        }
        guard letters.count >= 2, letters.allSatisfy({ positions[$0] != nil }) else { return [] }

        var best: [String: Double] = [:]
        func consider(_ edit: [Character], weight: Double) {
            guard !edit.isEmpty, let word = dictionary.bestForm(matching: String(edit)),
                  let count = dictionary.count(of: word) else { return }
            let score = log(Double(count)) + 3 * log(weight)
            if score > best[word] ?? -.infinity { best[word] = score }
        }

        for index in letters.indices {
            var deletion = letters
            deletion.remove(at: index)
            consider(deletion, weight: 0.6)

            if index + 1 < letters.count {
                var transposition = letters
                transposition.swapAt(index, index + 1)
                consider(transposition, weight: 0.9)
            }

            for letter in alphabet where letter != letters[index] {
                var substitution = letters
                substitution[index] = letter
                let isNeighbor = LetterLayout.areNeighbors(letter, letters[index], in: positions)
                consider(substitution, weight: isNeighbor ? 1 : 0.3)
            }
        }
        for index in 0...letters.count {
            for letter in alphabet {
                var insertion = letters
                insertion.insert(letter, at: index)
                let doubled = (index > 0 && letters[index - 1] == letter)
                    || (index < letters.count && letters[index] == letter)
                consider(insertion, weight: doubled ? 0.8 : 0.5)
            }
        }

        let typedLower = typed.lowercased()
        return best
            .filter { $0.key != typedLower }
            .map { Candidate(word: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

/// Reconoce palabras escritas deslizando el dedo comparando el trazo con el recorrido ideal
/// de cada palabra del diccionario (forma y posición), ponderado por su frecuencia.
struct GlideDecoder {
    let keyCenters: [Character: CGPoint]
    let keyWidth: CGFloat

    private static let sampleCount = 32

    func decode(
        path: [CGPoint],
        dictionary: WordDictionary,
        extraWords: [String: Int] = [:],
        limit: Int = 4
    ) -> [String] {
        guard path.count >= 2, keyWidth > 0,
              Self.length(of: path) >= Double(keyWidth) * 0.7,
              let start = path.first, let end = path.last else { return [] }

        let sampled = Self.resample(path, count: Self.sampleCount)
        let startKeys = nearestKeys(to: start)
        let endKeys = nearestKeys(to: end)
        guard !startKeys.isEmpty, !endKeys.isEmpty else { return [] }

        var scored: [String: Double] = [:]
        func evaluate(_ word: String, count: Int) {
            guard scored[word] == nil, let cost = cost(of: word, sampled: sampled) else { return }
            scored[word] = cost - 0.06 * log(Double(max(count, 1)))
        }

        for first in startKeys {
            for last in endKeys {
                for index in dictionary.glideCandidates(first: first, last: last) {
                    evaluate(dictionary.words[index], count: dictionary.counts[index])
                }
            }
        }
        for (word, count) in extraWords {
            let keys = WordDictionary.keyLetters(word)
            guard let first = keys.first, let last = keys.last,
                  startKeys.contains(first), endKeys.contains(last) else { continue }
            evaluate(word.lowercased(), count: count * 400)
        }

        return scored.sorted { $0.value < $1.value }.prefix(limit).map(\.key)
    }

    /// Coste de una palabra: forma del trazo más distancia a cada letra, en anchos de tecla.
    func cost(of word: String, sampled: [CGPoint]) -> Double? {
        var points: [CGPoint] = []
        for letter in WordDictionary.keyLetters(word) {
            // Letras sin tecla propia (ñ en QWERTY, ç en español…) se escriben en su tecla base.
            guard let center = keyCenters[letter] ?? LetterLayout.fallbackKey(for: letter).flatMap({ keyCenters[$0] }) else {
                if letter == "'" { continue }
                return nil
            }
            if points.last != center { points.append(center) }
        }
        guard points.count >= 2 else { return nil }

        // Alineación en orden de cada letra con el punto más cercano del trazo (programación
        // dinámica): todas las letras tienen que estar cerca del trazo y en el orden correcto.
        let width = Double(keyWidth)
        let threshold = width * 1.15
        var previous = [Double](repeating: 0, count: sampled.count)
        for (letterIndex, point) in points.enumerated() {
            var current = [Double](repeating: .infinity, count: sampled.count)
            var bestBefore = Double.infinity
            for index in sampled.indices {
                bestBefore = letterIndex == 0 ? 0 : min(bestBefore, previous[index])
                let distance = Self.distance(point, sampled[index])
                if distance <= threshold, bestBefore.isFinite {
                    current[index] = bestBefore + distance
                }
            }
            previous = current
        }
        guard let locationTotal = previous.min(), locationTotal.isFinite else { return nil }

        let ideal = Self.resample(points, count: sampled.count)
        var shapeTotal = 0.0
        for index in sampled.indices {
            shapeTotal += Self.distance(sampled[index], ideal[index])
        }

        let shape = shapeTotal / Double(sampled.count) / width
        let location = locationTotal / Double(points.count) / width
        return shape + 0.6 * location
    }

    private func nearestKeys(to point: CGPoint) -> [Character] {
        let radius = Double(keyWidth) * 1.05
        let sorted = keyCenters
            .map { (key: $0.key, distance: Self.distance($0.value, point)) }
            .sorted { $0.distance < $1.distance }
        guard let nearest = sorted.first else { return [] }
        let nearby = sorted.prefix(3).filter { $0.distance <= radius }.map(\.key)
        return nearby.isEmpty ? [nearest.key] : nearby
    }

    // MARK: Geometría

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func length(of path: [CGPoint]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Reparte `count` puntos a la misma distancia a lo largo del trazo.
    static func resample(_ path: [CGPoint], count: Int) -> [CGPoint] {
        guard let first = path.first, count > 1 else { return Array(path.prefix(count)) }
        let total = length(of: path)
        guard total > 0 else { return Array(repeating: first, count: count) }

        let step = total / Double(count - 1)
        var result = [first]
        var previous = first
        var accumulated = 0.0
        var index = 1
        while index < path.count, result.count < count {
            let current = path[index]
            let segment = distance(previous, current)
            if accumulated + segment >= step, segment > 0 {
                let ratio = (step - accumulated) / segment
                let point = CGPoint(
                    x: Double(previous.x) + ratio * Double(current.x - previous.x),
                    y: Double(previous.y) + ratio * Double(current.y - previous.y)
                )
                result.append(point)
                previous = point
                accumulated = 0
            } else {
                accumulated += segment
                previous = current
                index += 1
            }
        }
        while result.count < count, let last = path.last { result.append(last) }
        return result
    }
}
