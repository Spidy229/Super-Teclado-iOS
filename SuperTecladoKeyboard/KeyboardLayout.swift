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
    /// Ajustes rápidos (vibración, sonido…) y estado del acceso total.
    case settings
}

enum ShiftState {
    case off
    case on
    case locked
}

/// Distribución QWERTY española al estilo Gboard, con símbolos en pulsación larga.
enum KeyboardLayout {

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

    /// Símbolos de la esquina de cada letra según su posición (como la página ?123).
    static let positionHints: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["@", "#", "€", "_", "&", "-", "+", "(", ")", "/"],
        ["*", "\"", "'", ":", ";", "!", "?"]
    ]

    static func hint(row: Int, column: Int) -> String? {
        guard positionHints.indices.contains(row), positionHints[row].indices.contains(column) else { return nil }
        return positionHints[row][column]
    }

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
        "l": ["ł", "l·l"]
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

    static func letterAlternates(for key: String, hint: String?) -> [String] {
        var options: [String] = []
        if let hint { options.append(hint) }
        options += accents[key] ?? []
        if key == "'" { options += ["’", "‘", "\""] }
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
        /// Ocultar el teclado (fila inferior del iPad).
        case dismiss
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
    /// Fila de emojis y símbolos favoritos encima de las teclas (0 si está desactivada).
    var favoritesRowHeight: CGFloat = 0
    var isPad = false

    var totalHeight: CGFloat { stripHeight + favoritesRowHeight + keyAreaHeight }

    static func make(
        isPad: Bool,
        isLandscape: Bool,
        numberRow: Bool,
        scale: Double = 1,
        favoritesRow: Bool = false
    ) -> KeyboardMetrics {
        let baseRowHeight: CGFloat = isPad ? (isLandscape ? 66 : 58) : (isLandscape ? 40 : 54)
        let rowHeight = (baseRowHeight * CGFloat(scale)).rounded()
        let stripHeight: CGFloat = (isLandscape && !isPad) ? 36 : 44
        let rows: CGFloat = numberRow ? 4.78 : 4
        return KeyboardMetrics(
            rowHeight: rowHeight,
            stripHeight: stripHeight,
            keyAreaHeight: (rowHeight * rows).rounded() + 8,
            favoritesRowHeight: favoritesRow ? ((isLandscape && !isPad) ? 30 : 38) : 0,
            isPad: isPad
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
}

/// Centros de las letras tal y como se dibujan, que la tecla pasa al motor al empezar a deslizar.
struct GlideTarget {
    let centers: [Character: CGPoint]
    let keyWidth: CGFloat
}
