import Foundation

/// Idiomas del teclado: diccionario, corrector de iOS y distribución por defecto.
enum KeyboardLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case catalan = "ca"
    case portuguese = "pt"
    case english = "en"
    case french = "fr"
    case italian = "it"
    case german = "de"

    var id: Self { self }

    var title: String {
        switch self {
        case .spanish: "Español"
        case .catalan: "Catalán"
        case .portuguese: "Portugués"
        case .english: "Inglés"
        case .french: "Francés"
        case .italian: "Italiano"
        case .german: "Alemán"
        }
    }

    /// Nombre en el propio idioma, para la barra espaciadora.
    var nativeName: String {
        switch self {
        case .spanish: "Español"
        case .catalan: "Català"
        case .portuguese: "Português"
        case .english: "English"
        case .french: "Français"
        case .italian: "Italiano"
        case .german: "Deutsch"
        }
    }

    var dictionaryResource: String { "words-\(rawValue)" }

    var spellCheckerLanguage: String {
        switch self {
        case .spanish: "es_ES"
        case .catalan: "ca_ES"
        case .portuguese: "pt_BR"
        case .english: "en_US"
        case .french: "fr_FR"
        case .italian: "it_IT"
        case .german: "de_DE"
        }
    }

    var defaultLayout: LetterLayout {
        switch self {
        case .spanish: .spanish
        case .catalan, .portuguese: .cedilla
        case .english, .italian: .qwerty
        case .french: .azerty
        case .german: .qwertz
        }
    }
}

/// Distribución de las letras. Las posiciones se expresan en unidades de tecla.
enum LetterLayout: String, CaseIterable, Identifiable {
    case spanish
    case cedilla
    case qwerty
    case azerty
    case qwertz

    var id: Self { self }

    var title: String {
        switch self {
        case .spanish: "QWERTY español (ñ)"
        case .cedilla: "QWERTY con ç"
        case .qwerty: "QWERTY"
        case .azerty: "AZERTY"
        case .qwertz: "QWERTZ"
        }
    }

    var rows: [String] {
        switch self {
        case .spanish: ["qwertyuiop", "asdfghjklñ", "zxcvbnm"]
        case .cedilla: ["qwertyuiop", "asdfghjklç", "zxcvbnm"]
        case .qwerty: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .azerty: ["azertyuiop", "qsdfghjklm", "wxcvbn'"]
        case .qwertz: ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
        }
    }

    /// Las dos primeras filas se centran; la tercera va entre mayúsculas y borrar (1,5 teclas cada una).
    func offset(ofRow row: Int) -> Double {
        let count = Double(rows[row].count)
        return row < 2 ? (10 - count) / 2 : 1.5 + (7 - count) / 2
    }

    var unitPositions: [Character: (x: Double, y: Double)] {
        var positions: [Character: (x: Double, y: Double)] = [:]
        for (row, letters) in rows.enumerated() {
            for (column, letter) in letters.enumerated() {
                positions[letter] = (offset(ofRow: row) + Double(column) + 0.5, Double(row) + 0.5)
            }
        }
        return positions
    }

    /// Letras de la distribución (sin el apóstrofo de AZERTY).
    var alphabet: [Character] {
        Array(rows.joined().filter(\.isLetter))
    }

    static func areNeighbors(
        _ first: Character,
        _ second: Character,
        in positions: [Character: (x: Double, y: Double)]
    ) -> Bool {
        guard let a = positions[first], let b = positions[second] else { return false }
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot() <= 1.5
    }

    /// Tecla en la que se escribe una letra que no tiene tecla propia en esta distribución.
    static func fallbackKey(for letter: Character) -> Character? {
        switch letter {
        case "ñ": "n"
        case "ç": "c"
        case "ß": "s"
        case "œ": "o"
        case "æ": "a"
        default: nil
        }
    }
}
