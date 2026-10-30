import Foundation

enum AutoCapitalizationMode {
    case none
    case words
    case sentences
    case allCharacters
}

/// Reglas de edición del teclado independientes de UIKit para poder probarlas.
enum KeyboardTextLogic {
    static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]
    static let invertedOpeners: Set<Character> = ["¿", "¡"]
    static let closingCharacters: Set<Character> = [")", "\"", "'", "»", "”", "’"]

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
    }

    /// Palabra que se está escribiendo justo antes del cursor.
    static func currentWord(before context: String?) -> String {
        guard let context else { return "" }
        var characters: [Character] = []
        for character in context.reversed() {
            guard isWordCharacter(character) else { break }
            characters.append(character)
        }
        return String(characters.reversed())
    }

    static func shouldCapitalize(context: String?, mode: AutoCapitalizationMode) -> Bool {
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let last = context?.last else { return true }
            return last.isWhitespace || invertedOpeners.contains(last)
        case .sentences:
            return isSentenceStart(context ?? "")
        }
    }

    static func isSentenceStart(_ context: String) -> Bool {
        var index = context.endIndex
        while index > context.startIndex {
            let previous = context.index(before: index)
            let character = context[previous]
            guard character == " " || character == "\t" else { break }
            index = previous
        }
        guard index > context.startIndex else { return true }

        let hadTrailingSpace = index < context.endIndex
        let previousIndex = context.index(before: index)
        let character = context[previousIndex]
        if character.isNewline { return true }

        if invertedOpeners.contains(character) {
            return isSentenceStart(String(context[..<previousIndex]))
        }
        guard hadTrailingSpace else { return false }

        // Permite «Fin.» o (fin.) antes del espacio.
        var lookup = previousIndex
        var candidate = character
        while closingCharacters.contains(candidate), lookup > context.startIndex {
            lookup = context.index(before: lookup)
            candidate = context[lookup]
        }
        return sentenceTerminators.contains(candidate)
    }

    /// Punto automático al pulsar dos veces el espacio.
    static func shouldConvertDoubleSpace(context: String?) -> Bool {
        guard let context, context.hasSuffix(" ") else { return false }
        guard let previous = context.dropLast().last else { return false }
        if previous.isLetter || previous.isNumber || closingCharacters.contains(previous) { return true }
        return previous.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }

    /// Caracteres que se borran al eliminar una palabra hacia atrás.
    static func wordDeletionLength(context: String?) -> Int {
        guard let context, !context.isEmpty else { return 0 }
        let characters = Array(context.reversed())
        var index = 0
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        if index < characters.count, isWordCharacter(characters[index]) {
            while index < characters.count, isWordCharacter(characters[index]) { index += 1 }
        } else if index < characters.count {
            index += 1
        }
        return index
    }

    /// Desplazamiento (positivo) hasta el inicio de la palabra siguiente.
    static func nextWordOffset(after context: String?) -> Int {
        guard let context, !context.isEmpty else { return 0 }
        let characters = Array(context)
        var index = 0
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        if index < characters.count, isWordCharacter(characters[index]) {
            while index < characters.count, isWordCharacter(characters[index]) { index += 1 }
        } else if index < characters.count {
            index += 1
        }
        return index
    }

    static func offsetToLineStart(before context: String?) -> Int {
        guard let context else { return 0 }
        var count = 0
        for character in context.reversed() {
            if character.isNewline { break }
            count += 1
        }
        return count
    }

    static func offsetToLineEnd(after context: String?) -> Int {
        guard let context else { return 0 }
        var count = 0
        for character in context {
            if character.isNewline { break }
            count += 1
        }
        return count
    }

    /// Ajusta mayúsculas de una sugerencia a cómo se ha escrito la palabra.
    static func matchCase(_ suggestion: String, to typed: String) -> String {
        guard let first = typed.first else { return suggestion }
        if typed.count > 1, typed == typed.uppercased(), typed != typed.lowercased() {
            return suggestion.uppercased()
        }
        if first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }

    static func isLikelyOneTimeCode(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    /// Compara sin tildes ni mayúsculas, para decidir si una corrección es plausible.
    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }
}
