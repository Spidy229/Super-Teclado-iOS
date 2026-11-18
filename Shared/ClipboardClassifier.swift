import Foundation

/// Qué hacer con lo copiado que parece privado (tarjetas, IBAN, contraseñas, códigos).
enum SensitiveClipMode: String, CaseIterable, Identifiable {
    /// Se guarda oculto y se borra a los pocos minutos.
    case mask
    /// No se guarda.
    case skip
    /// Se guarda como cualquier otro elemento.
    case normal

    var id: Self { self }

    var title: String {
        switch self {
        case .mask: "Ocultar y borrar a los 2 minutos"
        case .skip: "No guardar"
        case .normal: "Guardar como el resto"
        }
    }
}

/// Reconoce el tipo de contenido copiado y si parece información privada.
enum ClipboardClassifier {
    /// Segundos que se conserva un elemento privado en Recientes.
    static let sensitiveLifetime: TimeInterval = 120

    static func isSensitive(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeyboardTextLogic.isLikelyOneTimeCode(value)
            || isCardNumber(value)
            || isIBAN(value)
            || looksLikePassword(value)
    }

    /// Número de tarjeta: 13-19 dígitos (con espacios o guiones) que superan el algoritmo de Luhn.
    static func isCardNumber(_ text: String) -> Bool {
        guard text.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) else { return false }
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// IBAN con dígitos de control válidos (módulo 97).
    static func isIBAN(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.range(of: #"^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$"#, options: .regularExpression) != nil else {
            return false
        }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            let value: Int
            if let digit = character.wholeNumberValue {
                value = digit
            } else if let ascii = character.asciiValue {
                value = Int(ascii) - 55
            } else {
                return false
            }
            for digit in String(value) {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    /// Contraseña generada: sin espacios y con minúsculas, mayúsculas, números y símbolos.
    static func looksLikePassword(_ text: String) -> Bool {
        guard (10...64).contains(text.count),
              !text.contains(where: \.isWhitespace),
              !text.contains("://"), !text.contains("@") else { return false }
        let hasLower = text.contains(where: \.isLowercase)
        let hasUpper = text.contains(where: \.isUppercase)
        let hasDigit = text.contains(where: \.isNumber)
        let hasSymbol = text.contains { !$0.isLetter && !$0.isNumber }
        return hasLower && hasUpper && hasDigit && hasSymbol
    }

    /// Dominio de un enlace sin «www.», para mostrarlo en el historial.
    static func linkDomain(_ text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Color en formato «#RRGGBB».
    static func hexColor(_ text: String) -> (red: Double, green: Double, blue: Double)? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^#?[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil,
              let number = Int(value.replacingOccurrences(of: "#", with: ""), radix: 16) else { return nil }
        return (
            Double((number >> 16) & 0xFF) / 255,
            Double((number >> 8) & 0xFF) / 255,
            Double(number & 0xFF) / 255
        )
    }

    /// Transformaciones de «Pegar como…».
    enum Transform: String, CaseIterable, Identifiable {
        case uppercase
        case lowercase
        case capitalized
        case singleLine
        case trimmed

        var id: Self { self }

        var title: String {
            switch self {
            case .uppercase: "MAYÚSCULAS"
            case .lowercase: "minúsculas"
            case .capitalized: "Tipo Título"
            case .singleLine: "En una línea"
            case .trimmed: "Sin espacios de más"
            }
        }

        func apply(to text: String) -> String {
            switch self {
            case .uppercase:
                return text.uppercased()
            case .lowercase:
                return text.lowercased()
            case .capitalized:
                return text.capitalized
            case .singleLine:
                return text.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            case .trimmed:
                return text.split(whereSeparator: \.isNewline)
                    .map { line in line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
