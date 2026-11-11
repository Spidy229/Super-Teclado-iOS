import UIKit
import Foundation

extension KeyGridConfiguration {
    /// Configuración de la cuadrícula a partir del estado actual del motor. La usan SwiftUI y la
    /// propia cuadrícula, que se actualiza al instante tras cada pulsación sin esperar a SwiftUI.
    @MainActor
    init(engine: KeyboardEngine) {
        self.init(
            rows: engine.keyRows(),
            showsNumberRow: engine.page == .letters && engine.preferences.numberRow,
            page: engine.page,
            shift: engine.shift,
            returnKeyType: engine.returnKeyType,
            spaceTitle: engine.spaceBarTitle,
            keyBorders: engine.preferences.keyBorders,
            keyPopups: engine.preferences.keyPopups,
            labelScale: CGFloat(engine.preferences.keyLabelSize.scale),
            longPressDelay: engine.preferences.longPressDelay,
            showsGlideTrail: engine.preferences.glideTrail
        )
    }
}

/// Construye las filas de teclas para la página actual y el tipo de campo.
extension KeyboardEngine {
    /// Filas de teclas de la página actual.
    func keyRows() -> [[KeySpec]] {
        switch page {
        case .letters: letterRows()
        case .numbers: symbolPageRows(KeyboardLayout.numberRows, toggle: .page(.symbols, "=\\<"))
        case .symbols: symbolPageRows(KeyboardLayout.symbolRows, toggle: .page(.numbers, "?123"))
        case .numberPad: numberPadRows()
        }
    }

    private func letterRows() -> [[KeySpec]] {
        var rows: [[KeySpec]] = []
        if preferences.numberRow {
            rows.append(KeyboardLayout.numberRow.map { digit in
                KeySpec(
                    id: "n-\(digit)",
                    kind: .character(digit),
                    units: 1,
                    alternates: KeyboardLayout.symbolAlternates[digit] ?? []
                )
            })
        }
        for (index, letters) in letterLayout.rows.enumerated() {
            // Con fila de números, los dígitos de la primera fila sobran (como en Gboard).
            let includeHint = preferences.longPressSymbols && !(preferences.numberRow && index == 0)
            var row = letters.enumerated().map { column, character in
                let letter = String(character)
                let hint = includeHint ? KeyboardLayout.hint(row: index, column: column) : nil
                return KeySpec(
                    id: "l-\(letter)",
                    kind: .character(letter),
                    units: 1,
                    hint: hint,
                    alternates: KeyboardLayout.letterAlternates(for: letter, hint: hint),
                    isLetter: character.isLetter
                )
            }
            if metrics.isPad {
                // Como el teclado grande de iPad: borrar e intro a la derecha, «,» «.» y dos mayúsculas.
                switch index {
                case 0:
                    row.append(KeySpec(id: "delete", kind: .delete, units: 1.5))
                case 1:
                    row.append(KeySpec(id: "return", kind: .returnKey, units: 1.75))
                default:
                    row.insert(KeySpec(id: "shift", kind: .shift, units: 1.25), at: 0)
                    row.append(contentsOf: [commaKey(), periodKey()])
                    row.append(KeySpec(id: "shift2", kind: .shift, units: 1.25))
                }
            } else if index == 2 {
                row.insert(KeySpec(id: "shift", kind: .shift, units: 1.5), at: 0)
                row.append(KeySpec(id: "delete", kind: .delete, units: 1.5))
            }
            rows.append(row)
        }
        rows.append(metrics.isPad ? padBottomRow() : bottomRow())
        return rows
    }

    private func padBottomRow() -> [KeySpec] {
        let switcher = needsInputModeSwitchKey
            ? KeySpec(id: "globe", kind: .globe, units: 1.25)
            : KeySpec(id: "emoji", kind: .emoji, units: 1.25)
        return [
            KeySpec(id: "page", kind: .page(.numbers, "?123"), units: 1.5),
            switcher,
            KeySpec(id: "space", kind: .space, units: 5.5),
            KeySpec(id: "page2", kind: .page(.numbers, "?123"), units: 1.5),
            KeySpec(id: "dismiss", kind: .dismiss, units: 1.25)
        ]
    }

    private func symbolPageRows(_ source: [[String]], toggle: KeySpec.Kind) -> [[KeySpec]] {
        var rows: [[KeySpec]] = source.enumerated().map { rowIndex, symbols in
            symbols.map { symbol in
                KeySpec(
                    id: "s\(rowIndex)-\(symbol)",
                    kind: .character(symbol),
                    units: 1,
                    alternates: KeyboardLayout.symbolAlternates[symbol] ?? []
                )
            }
        }
        rows[2].insert(KeySpec(id: "toggle", kind: toggle, units: 1.5), at: 0)
        rows[2].append(KeySpec(id: "delete", kind: .delete, units: 1.5))
        rows.append(bottomRow())
        return rows
    }

    private func commaKey() -> KeySpec {
        if isEmailField {
            return KeySpec(id: "comma", kind: .character("@"), units: 1, alternates: ["_", "-", "+"])
        }
        if isWebField {
            return KeySpec(id: "comma", kind: .character("/"), units: 1, alternates: [":", "-", "_", "?"])
        }
        return KeySpec(id: "comma", kind: .character(","), units: 1, alternates: KeyboardLayout.commaAlternates)
    }

    private func periodKey() -> KeySpec {
        KeySpec(
            id: "period",
            kind: .character("."),
            units: 1,
            alternates: (isWebField || isEmailField)
                ? KeyboardLayout.webAlternates
                : KeyboardLayout.periodAlternates
        )
    }

    private func bottomRow() -> [KeySpec] {
        let pageKey = page == .letters
            ? KeySpec(id: "page", kind: .page(.numbers, "?123"), units: 1.5)
            : KeySpec(id: "page", kind: .page(.letters, "ABC"), units: 1.5)
        let comma = commaKey()
        let period = periodKey()
        let switcher = needsInputModeSwitchKey
            ? KeySpec(id: "globe", kind: .globe, units: 1)
            : KeySpec(id: "emoji", kind: .emoji, units: 1)

        return [
            pageKey,
            comma,
            switcher,
            KeySpec(id: "space", kind: .space, units: 4),
            period,
            KeySpec(id: "return", kind: .returnKey, units: 1.5)
        ]
    }

    private func numberPadRows() -> [[KeySpec]] {
        let isPhone = keyboardType == .phonePad
        let decimal = Locale.current.decimalSeparator ?? ","
        func digit(_ value: String, _ alternates: [String] = []) -> KeySpec {
            KeySpec(id: "d-\(value)", kind: .character(value), units: 2.5, alternates: alternates)
        }
        return [
            [digit("1"), digit("2"), digit("3"), isPhone ? digit("+") : digit("-", ["+", "*", "/"])],
            [digit("4"), digit("5"), digit("6"), KeySpec(id: "space", kind: .space, units: 2.5)],
            [digit("7"), digit("8"), digit("9"), KeySpec(id: "delete", kind: .delete, units: 2.5)],
            [
                isPhone ? digit("*", ["#", ",", ";"]) : KeySpec(id: "page", kind: .page(.numbers, "!#1"), units: 2.5),
                digit("0"),
                isPhone ? digit("#") : digit(decimal, [decimal == "," ? "." : ","]),
                KeySpec(id: "return", kind: .returnKey, units: 2.5)
            ]
        ]
    }
}
