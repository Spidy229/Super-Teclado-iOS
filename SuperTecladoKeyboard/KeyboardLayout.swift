import CoreGraphics
import Foundation

enum KeyboardPage: Equatable {
    case letters
    case numbers
    case symbols
    case numberPad
}

enum KeyboardPanel: Equatable {
    case typing
    case clipboard
    case emoji
    /// Búsqueda de emojis: las letras escriben en el buscador, no en el documento.
    case emojiSearch
    /// Búsqueda en el portapapeles, también escrita con el teclado.
    case clipboardSearch
    case editing
    /// Selector de temas dentro del teclado.
    case themes
}

enum ShiftState {
    case off
    case on
    case locked
}

/// Distribución QWERTY española al estilo Gboard, con símbolos en pulsación larga.
enum KeyboardLayout {
    static let letterRows: [[String]] = QwertyGeometry.rows.map { $0.map(String.init) }

    static let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    static let numberRows: [[String]] = [
        numberRow,
        ["@", "#", "€", "_", "&", "-", "+", "(", ")", "/"],
        ["*", "\"", "'", ":", ";", "!", "?"]
    ]

    static let symbolRows: [[String]] = [
        ["~", "`", "|", "•", "√", "π", "÷", "×", "¶", "∆"],
        ["£", "¢", "$", "¥", "^", "°", "=", "{", "}", "\\"],
        ["%", "©", "®", "™", "✓", "[", "]"]
    ]

    /// Símbolo que aparece en la esquina de cada letra (igual que la página ?123).
    static let letterHints: [String: String] = [
        "q": "1", "w": "2", "e": "3", "r": "4", "t": "5", "y": "6", "u": "7", "i": "8", "o": "9", "p": "0",
        "a": "@", "s": "#", "d": "€", "f": "_", "g": "&", "h": "-", "j": "+", "k": "(", "l": ")", "ñ": "/",
        "z": "*", "x": "\"", "c": "'", "v": ":", "b": ";", "n": "!", "m": "?"
    ]

    static let accents: [String: [String]] = [
        "a": ["á", "à", "ä", "â", "ã", "å", "æ", "ª"],
        "e": ["é", "è", "ë", "ê", "ē", "ę"],
        "i": ["í", "ì", "ï", "î"],
        "o": ["ó", "ò", "ö", "ô", "õ", "ø", "œ", "º"],
        "u": ["ú", "ü", "ù", "û"],
        "n": ["ñ", "ń"],
        "c": ["ç", "ć", "č"],
        "s": ["ß", "ś", "š"],
        "y": ["ý", "ÿ"],
        "z": ["ž", "ź", "ż"],
        "l": ["ł"]
    ]

    static let symbolAlternates: [String: [String]] = [
        "1": ["¹", "½", "⅓", "¼", "⅛"],
        "2": ["²", "⅔"],
        "3": ["³", "¾", "⅜"],
        "4": ["⁴"],
        "0": ["ⁿ", "∅", "°"],
        "-": ["–", "—", "·", "_"],
        "/": ["\\", "|"],
        "€": ["$", "£", "¥", "¢", "₩", "₹"],
        "$": ["€", "£", "¥", "¢"],
        "\"": ["“", "”", "«", "»", "„"],
        "'": ["‘", "’", "‚", "‹", "›"],
        "?": ["¿", "‽"],
        "!": ["¡"],
        "(": ["<", "[", "{"],
        ")": [">", "]", "}"],
        "&": ["§"],
        "+": ["±"],
        "*": ["★", "†", "‡"],
        "%": ["‰", "℅"],
        "=": ["≠", "≈", "∞"],
        "#": ["№"],
        "_": ["‾"]
    ]

    static let periodAlternates = ["?", "!", "¿", "¡", "…", ":", ";", "-", "\"", "'"]
    static let commaAlternates = ["¿", "¡", ";", ":", "'", "\"", "-"]
    static let webAlternates = [".com", ".es", ".org", ".net", ".mx", "/", ":"]

    static func letterAlternates(for key: String, includeHint: Bool) -> [String] {
        var options: [String] = []
        if includeHint, let hint = letterHints[key] { options.append(hint) }
        options += accents[key] ?? []
        return options
    }
}

struct KeySpec: Identifiable {
    enum Kind: Equatable {
        case character(String)
        case shift
        case delete
        case space
        case returnKey
        case globe
        case emoji
        case page(KeyboardPage, String)
    }

    let id: String
    let kind: Kind
    let units: CGFloat
    var hint: String? = nil
    var alternates: [String] = []
    var isLetter = false
}

struct KeyboardMetrics: Equatable {
    var rowHeight: CGFloat
    var stripHeight: CGFloat
    var keyAreaHeight: CGFloat

    var totalHeight: CGFloat { stripHeight + keyAreaHeight }

    static func make(isPad: Bool, isLandscape: Bool, numberRow: Bool, scale: Double = 1) -> KeyboardMetrics {
        let baseRowHeight: CGFloat = isPad ? (isLandscape ? 66 : 58) : (isLandscape ? 40 : 54)
        let rowHeight = (baseRowHeight * CGFloat(scale)).rounded()
        let stripHeight: CGFloat = (isLandscape && !isPad) ? 36 : 44
        let rows: CGFloat = numberRow ? 4.78 : 4
        return KeyboardMetrics(
            rowHeight: rowHeight,
            stripHeight: stripHeight,
            keyAreaHeight: (rowHeight * rows).rounded() + 8
        )
    }
}

/// Geometría de la cuadrícula de teclas. La usan tanto la vista como el reconocimiento de la
/// escritura deslizando, para que el trazo y los centros de las teclas coincidan.
struct KeyGridGeometry {
    static let horizontalPadding: CGFloat = 3
    static let verticalPadding: CGFloat = 4
    static let numberRowScale: CGFloat = 0.78

    let size: CGSize
    let showsNumberRow: Bool
    let rowCount: Int

    var unit: CGFloat { (size.width - Self.horizontalPadding * 2) / 10 }

    var rowHeight: CGFloat {
        let available = size.height - Self.verticalPadding * 2
        let rows = showsNumberRow
            ? CGFloat(max(rowCount - 1, 1)) + Self.numberRowScale
            : CGFloat(max(rowCount, 1))
        return available / rows
    }

    func height(ofRow index: Int) -> CGFloat {
        showsNumberRow && index == 0 ? rowHeight * Self.numberRowScale : rowHeight
    }

    func originY(ofRow index: Int) -> CGFloat {
        (0..<index).reduce(Self.verticalPadding) { $0 + height(ofRow: $1) }
    }

    /// Centro de cada letra en la página de letras, en coordenadas de la cuadrícula.
    func letterCenters() -> [Character: CGPoint] {
        var centers: [Character: CGPoint] = [:]
        let firstLetterRow = showsNumberRow ? 1 : 0
        for (row, letters) in QwertyGeometry.rows.enumerated() {
            let rowIndex = firstLetterRow + row
            let y = originY(ofRow: rowIndex) + height(ofRow: rowIndex) / 2
            for (column, letter) in letters.enumerated() {
                let offset = CGFloat(QwertyGeometry.rowOffsets[row]) + CGFloat(column) + 0.5
                centers[letter] = CGPoint(x: Self.horizontalPadding + offset * unit, y: y)
            }
        }
        return centers
    }
}
