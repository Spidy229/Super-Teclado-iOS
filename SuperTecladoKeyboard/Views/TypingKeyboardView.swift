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

/// Construye las filas de teclas para la página actual y reparte el ancho en unidades.
private struct KeyGridView: View {
    @EnvironmentObject private var engine: KeyboardEngine
    @Environment(\.keyboardPalette) private var palette
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let rows = makeRows()
        let geometry = KeyGridGeometry(
            size: CGSize(width: width, height: height),
            showsNumberRow: engine.page == .letters && engine.preferences.numberRow,
            rowCount: rows.count
        )
        let horizontalPadding = KeyGridGeometry.horizontalPadding
        let unit = geometry.unit

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let currentHeight = geometry.height(ofRow: index)
                let originY = geometry.originY(ofRow: index)
                let rowWidth = row.reduce(0) { $0 + $1.units } * unit
                let inset = max(0, (width - horizontalPadding * 2 - rowWidth) / 2)
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { keyIndex, spec in
                        let originX = horizontalPadding + inset
                            + row.prefix(keyIndex).reduce(0) { $0 + $1.units } * unit
                        keyView(
                            for: spec,
                            size: CGSize(width: spec.units * unit, height: currentHeight),
                            origin: CGPoint(x: originX, y: originY)
                        )
                    }
                }
                .frame(width: width - horizontalPadding * 2)
                // Las filas inferiores van encima para que sus ventanas emergentes cubran la fila superior.
                .zIndex(Double(index))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, KeyGridGeometry.verticalPadding)
        .frame(width: width, height: height)
        .overlay {
            if engine.preferences.glideTrail {
                GlideTrailView(trail: engine.glideTrail, color: palette.accent)
            }
        }
    }

    @ViewBuilder
    private func keyView(for spec: KeySpec, size: CGSize, origin: CGPoint) -> some View {
        switch spec.kind {
        case .character(let value):
            CharacterKeyView(
                value: value,
                hint: spec.hint,
                alternates: spec.alternates,
                caseSensitive: spec.isLetter,
                size: size,
                origin: origin,
                gridSize: CGSize(width: width, height: height)
            )
        case .shift:
            FunctionKeyView(
                size: size,
                fill: engine.shift == .off ? nil : palette.key,
                accessibilityText: "Mayúsculas",
                action: { engine.tapShift() }
            ) {
                Image(systemName: shiftSymbol)
                    .font(.system(size: min(20, size.height * 0.38), weight: .medium))
                    .foregroundStyle(engine.shift == .locked ? palette.accent : palette.text)
            }
        case .delete:
            DeleteKeyView(size: size)
        case .space:
            SpaceKeyView(size: size)
        case .returnKey:
            FunctionKeyView(
                size: size,
                fill: palette.accent,
                alwaysFilled: true,
                accessibilityText: "Intro",
                action: { engine.insertReturn() }
            ) {
                Image(systemName: returnSymbol)
                    .font(.system(size: min(20, size.height * 0.38), weight: .semibold))
                    .foregroundStyle(palette.accentText)
            }
        case .globe:
            FunctionKeyView(size: size, accessibilityText: "Siguiente teclado", action: { engine.advanceToNextInputMode() }) {
                Image(systemName: "globe")
                    .font(.system(size: min(19, size.height * 0.36)))
                    .foregroundStyle(palette.text)
            }
        case .emoji:
            FunctionKeyView(size: size, accessibilityText: "Emojis", action: { engine.open(.emoji) }) {
                Image(systemName: "face.smiling")
                    .font(.system(size: min(20, size.height * 0.38)))
                    .foregroundStyle(palette.text)
            }
        case .page(let target, let title):
            FunctionKeyView(size: size, accessibilityText: title, action: { engine.setPage(target) }) {
                Text(title)
                    .font(.system(size: min(15, size.height * 0.3), weight: .medium))
                    .foregroundStyle(palette.text)
            }
        }
    }

    private var shiftSymbol: String {
        switch engine.shift {
        case .off: "shift"
        case .on: "shift.fill"
        case .locked: "capslock.fill"
        }
    }

    private var returnSymbol: String {
        switch engine.returnKeyType {
        case .go, .join, .continue: "arrow.right"
        case .google, .search, .yahoo: "magnifyingglass"
        case .send: "paperplane.fill"
        case .next: "arrow.right.to.line"
        case .done: "checkmark"
        case .route: "arrow.triangle.turn.up.right.diamond"
        case .emergencyCall: "phone.fill"
        default: "return"
        }
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
            if index == 2 {
                row.insert(KeySpec(id: "shift", kind: .shift, units: 1.5), at: 0)
                row.append(KeySpec(id: "delete", kind: .delete, units: 1.5))
            }
            rows.append(row)
        }
        rows.append(bottomRow())
        return rows
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

    private func bottomRow() -> [KeySpec] {
        let pageKey = engine.page == .letters
            ? KeySpec(id: "page", kind: .page(.numbers, "?123"), units: 1.5)
            : KeySpec(id: "page", kind: .page(.letters, "ABC"), units: 1.5)

        let comma: KeySpec
        if engine.isEmailField {
            comma = KeySpec(id: "comma", kind: .character("@"), units: 1, alternates: ["_", "-", "+"])
        } else if engine.isWebField {
            comma = KeySpec(id: "comma", kind: .character("/"), units: 1, alternates: [":", "-", "_", "?"])
        } else {
            comma = KeySpec(id: "comma", kind: .character(","), units: 1, alternates: KeyboardLayout.commaAlternates)
        }

        let period = KeySpec(
            id: "period",
            kind: .character("."),
            units: 1,
            alternates: (engine.isWebField || engine.isEmailField)
                ? KeyboardLayout.webAlternates
                : KeyboardLayout.periodAlternates
        )
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
