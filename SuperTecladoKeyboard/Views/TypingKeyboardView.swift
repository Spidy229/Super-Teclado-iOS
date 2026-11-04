import SwiftUI

struct TypingKeyboardView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let mode = engine.preferences.oneHandedMode
            let sideWidth: CGFloat = mode == .off ? 0 : min(72, proxy.size.width * 0.17)
            HStack(spacing: 0) {
                if mode == .right { oneHandedPanel(width: sideWidth, height: proxy.size.height) }
                KeyGridView(width: proxy.size.width - sideWidth, height: proxy.size.height)
                if mode == .left { oneHandedPanel(width: sideWidth, height: proxy.size.height) }
            }
        }
    }

    private func oneHandedPanel(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 18) {
            Button { engine.setOneHandedMode(.off) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: width, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Salir del modo una mano")
            Button {
                engine.setOneHandedMode(engine.preferences.oneHandedMode == .right ? .left : .right)
            } label: {
                Image(systemName: engine.preferences.oneHandedMode == .right ? "chevron.right" : "chevron.left")
                    .frame(width: width, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Cambiar de lado")
        }
        .buttonStyle(.plain)
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(palette.text.opacity(0.8))
        .frame(width: width, height: height)
    }
}

/// Construye las filas de teclas para la página actual. Las teclas las dibuja y las toca
/// `KeyGridUIView` (UIKit), que solo se actualiza cuando cambia algo de lo que muestra.
private struct KeyGridView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        KeyGridRepresentable(engine: engine, configuration: configuration, palette: palette)
            .frame(width: width, height: height)
    }

    private var configuration: KeyGridConfiguration {
        KeyGridConfiguration(
            rows: makeRows(),
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

    // MARK: Filas

    private func makeRows() -> [[KeySpec]] {
        switch engine.page {
        case .letters: letterRows()
        case .numbers: symbolPageRows(KeyboardLayout.numberRows, toggle: .page(.symbols, "=\\<"))
        case .symbols: symbolPageRows(KeyboardLayout.symbolRows, toggle: .page(.numbers, "?123"))
        case .numberPad: numberPadRows()
        }
    }

    private func letterRows() -> [[KeySpec]] {
        var rows: [[KeySpec]] = []
        if engine.preferences.numberRow {
            rows.append(KeyboardLayout.numberRow.map { digit in
                KeySpec(
                    id: "n-\(digit)",
                    kind: .character(digit),
                    units: 1,
                    alternates: KeyboardLayout.symbolAlternates[digit] ?? []
                )
            })
        }
        for (index, letters) in engine.letterLayout.rows.enumerated() {
            // Con fila de números, los dígitos de la primera fila sobran (como en Gboard).
            let includeHint = engine.preferences.longPressSymbols && !(engine.preferences.numberRow && index == 0)
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
            if engine.metrics.isPad {
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
        rows.append(engine.metrics.isPad ? padBottomRow() : bottomRow())
        return rows
    }

    private func padBottomRow() -> [KeySpec] {
        let switcher = engine.needsInputModeSwitchKey
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
        if engine.isEmailField {
            return KeySpec(id: "comma", kind: .character("@"), units: 1, alternates: ["_", "-", "+"])
        }
        if engine.isWebField {
            return KeySpec(id: "comma", kind: .character("/"), units: 1, alternates: [":", "-", "_", "?"])
        }
        return KeySpec(id: "comma", kind: .character(","), units: 1, alternates: KeyboardLayout.commaAlternates)
    }

    private func periodKey() -> KeySpec {
        KeySpec(
            id: "period",
            kind: .character("."),
            units: 1,
            alternates: (engine.isWebField || engine.isEmailField)
                ? KeyboardLayout.webAlternates
                : KeyboardLayout.periodAlternates
        )
    }

    private func bottomRow() -> [KeySpec] {
        let pageKey = engine.page == .letters
            ? KeySpec(id: "page", kind: .page(.numbers, "?123"), units: 1.5)
            : KeySpec(id: "page", kind: .page(.letters, "ABC"), units: 1.5)
        let comma = commaKey()
        let period = periodKey()
        let switcher = engine.needsInputModeSwitchKey
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
        let isPhone = engine.keyboardType == .phonePad
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
