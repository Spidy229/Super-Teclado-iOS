import SwiftUI
import UIKit

@MainActor
private final class KeyboardViewModel: ObservableObject {
    @Published var savedClips: [SharedClipboardClip] = []
    @Published var temporaryClips: [SharedTemporaryClip] = []
    @Published var hasFullAccess = false
}

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardViewModel()
    private var host: UIHostingController<SuperTecladoView>?
    private var clipboardTimer: Timer?
    private var lastInspectedPasteboardChangeCount: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
        installKeyboardView()
        let height = view.heightAnchor.constraint(equalToConstant: 342)
        height.priority = .defaultHigh
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastInspectedPasteboardChangeCount = nil
        captureClipboardAsTemporaryIfNeeded()
        reload()
        startClipboardMonitoring()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        captureClipboardAsTemporaryIfNeeded()
        reload()
    }

    @discardableResult
    private func captureClipboardAsTemporaryIfNeeded(automatic: Bool = true) -> Bool {
        guard (!automatic || SharedClipboardStore.automaticCaptureEnabled),
              hasFullAccess else {
            return false
        }

        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        guard (!automatic || lastInspectedPasteboardChangeCount != changeCount),
              SharedClipboardStore.shouldCapture(pasteboardChangeCount: changeCount) else {
            return false
        }
        lastInspectedPasteboardChangeCount = changeCount
        guard let text = pasteboard.string else { return false }
        return captureTextAsTemporaryIfAllowed(text, pasteboardChangeCount: changeCount)
    }

    @discardableResult
    private func captureTextAsTemporaryIfAllowed(_ text: String, pasteboardChangeCount: Int) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (!SharedClipboardStore.skipOneTimeCodes || !isLikelyOneTimeCode(text)) else {
            return false
        }
        return SharedClipboardStore.captureTemporaryText(
            text,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }

    private func startClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(
            timeInterval: 0.7,
            target: self,
            selector: #selector(pollClipboard),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func pollClipboard() {
        let captured = captureClipboardAsTemporaryIfNeeded()
        let now = Date.now
        let hasExpiredTemporary = model.temporaryClips.contains {
            $0.expiresAt.map { $0 <= now } ?? false
        }
        if captured || hasExpiredTemporary || model.hasFullAccess != hasFullAccess { reload() }
    }

    private func isLikelyOneTimeCode(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    private func installKeyboardView() {
        let controller = UIHostingController(rootView: makeView())
        controller.view.backgroundColor = .clear
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        host = controller
    }

    private func makeView() -> SuperTecladoView {
        SuperTecladoView(
            model: model,
            insertSaved: { [weak self] clip in
                guard let self else { return }
                guard let current = SharedClipboardStore.load().first(where: { $0.id == clip.id }) else {
                    self.reload()
                    return
                }
                self.textDocumentProxy.insertText(current.text)
                SharedClipboardStore.markUsed(id: current.id)
                self.reload()
            },
            insertTemporary: { [weak self] clip in
                guard let self else { return }
                guard let current = SharedClipboardStore.loadTemporaryInbox().first(where: { $0.id == clip.id }) else {
                    self.reload()
                    return
                }
                self.textDocumentProxy.insertText(current.text)
                SharedClipboardStore.markTemporaryUsed(id: current.id)
                self.reload()
            },
            saveTemporary: { [weak self] clip in
                guard self?.hasFullAccess == true else { return }
                SharedClipboardStore.promoteTemporary(id: clip.id)
                self?.reload()
            },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            toggleFavorite: { [weak self] clip in
                SharedClipboardStore.toggleFavorite(id: clip.id)
                self?.reload()
            },
            refresh: { [weak self] in
                self?.captureClipboardAsTemporaryIfNeeded(automatic: false)
                self?.reload()
            },
            paste: { [weak self] in
                guard let self, self.hasFullAccess else { return }
                let pasteboard = UIPasteboard.general
                let changeCount = pasteboard.changeCount
                guard let text = pasteboard.string,
                      !text.isEmpty else { return }
                self.lastInspectedPasteboardChangeCount = changeCount
                self.captureTextAsTemporaryIfAllowed(text, pasteboardChangeCount: changeCount)
                self.textDocumentProxy.insertText(text)
                self.reload()
            },
            delete: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            insertSpace: { [weak self] in self?.textDocumentProxy.insertText(" ") },
            insertReturn: { [weak self] in self?.textDocumentProxy.insertText("\n") },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() }
        )
    }

    private func reload() {
        model.savedClips = SharedClipboardStore.load()
        model.temporaryClips = SharedClipboardStore.loadTemporaryInbox()
        model.hasFullAccess = hasFullAccess
    }
}

private enum KeyboardMode { case typing, clipboard }
private enum KeyboardPage { case letters, numbers, symbols }
private enum KeyboardSection: String, CaseIterable, Identifiable {
    case temporary = "Temporales"
    case saved = "Guardados"
    var id: Self { self }
}

private struct SuperTecladoView: View {
    @ObservedObject var model: KeyboardViewModel
    let insertSaved: (SharedClipboardClip) -> Void
    let insertTemporary: (SharedTemporaryClip) -> Void
    let saveTemporary: (SharedTemporaryClip) -> Void
    let insertText: (String) -> Void
    let toggleFavorite: (SharedClipboardClip) -> Void
    let refresh: () -> Void
    let paste: () -> Void
    let delete: () -> Void
    let insertSpace: () -> Void
    let insertReturn: () -> Void
    let nextKeyboard: () -> Void

    @State private var mode: KeyboardMode = .typing
    @State private var page: KeyboardPage = .letters
    @State private var isShifted = false
    @State private var section: KeyboardSection = .temporary

    private let background = Color(red: 0.105, green: 0.11, blue: 0.125)
    private let toolbarBackground = Color(red: 0.12, green: 0.125, blue: 0.14)
    private let keyBackground = Color(red: 0.285, green: 0.29, blue: 0.305)
    private let specialBackground = Color(red: 0.18, green: 0.185, blue: 0.205)
    private let accent = Color(red: 0.05, green: 0.68, blue: 0.96)

    var body: some View {
        VStack(spacing: 0) {
            if mode == .typing {
                typingToolbar
                typingKeyboard
            } else {
                clipboardToolbar
                clipboardPanel
            }
        }
        .background(background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var typingToolbar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent)
                Text("S").font(.headline.bold()).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            Text("Super Teclado")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 0)
            toolbarButton("clipboard.fill", selected: false) {
                refresh()
                mode = .clipboard
                section = .temporary
            }
            toolbarButton("ellipsis", selected: false) {
                page = page == .letters ? .numbers : .letters
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(toolbarBackground)
    }

    private var clipboardToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "clipboard.fill").foregroundStyle(accent)
            Text("Portapapeles").font(.headline)
            Spacer(minLength: 0)
            toolbarButton("keyboard", selected: true) { mode = .typing }
            toolbarButton("square.grid.2x2", selected: false) {
                section = section == .temporary ? .saved : .temporary
            }
            toolbarButton("arrow.clockwise", selected: false, action: refresh)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(toolbarBackground)
    }

    private func toolbarButton(
        _ symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 34)
                .background(selected ? accent : specialBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var typingKeyboard: some View {
        VStack(spacing: 7) {
            if page == .letters {
                characterRow(Array("qwertyuiop").map(String.init))
                characterRow(Array("asdfghjklñ").map(String.init), inset: 17)
                HStack(spacing: 6) {
                    specialKey(isShifted ? "shift.fill" : "shift", width: 48) { isShifted.toggle() }
                    ForEach(Array("zxcvbnm").map(String.init), id: \.self) { character in
                        characterKey(character)
                    }
                    specialKey("delete.left", width: 48, action: delete)
                }
            } else {
                characterRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
                characterRow(page == .numbers
                    ? ["@", "#", "€", "_", "&", "-", "+", "(", ")", "/"]
                    : ["~", "`", "|", "•", "√", "π", "÷", "×", "{", "}"])
                HStack(spacing: 6) {
                    textSpecialKey(page == .numbers ? "#+=" : "123", width: 48) {
                        page = page == .numbers ? .symbols : .numbers
                    }
                    ForEach(page == .numbers
                        ? [".", ",", "'", ":", ";", "!", "?"]
                        : ["*", "\"", "%", "©", "®", "™", "<"], id: \.self) { character in
                        characterKey(character)
                    }
                    specialKey("delete.left", width: 48, action: delete)
                }
            }
            bottomTypingRow
        }
        .padding(.horizontal, 5)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
    }

    private var bottomTypingRow: some View {
        HStack(spacing: 6) {
            textSpecialKey(page == .letters ? "123" : "ABC", width: 58) {
                page = page == .letters ? .numbers : .letters
                isShifted = false
            }
            specialKey("globe", width: 48, action: nextKeyboard)
            Button(action: insertSpace) {
                Text("espacio")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 47)
                    .background(keyBackground, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(KeyboardPressStyle())
            Button(action: insertReturn) {
                Text("intro")
                    .font(.subheadline)
                    .frame(width: 72, height: 47)
                    .background(specialBackground, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(KeyboardPressStyle())
        }
    }

    private func characterRow(_ characters: [String], inset: CGFloat = 0) -> some View {
        HStack(spacing: 6) {
            ForEach(characters, id: \.self) { character in characterKey(character) }
        }
        .padding(.horizontal, inset)
    }

    private func characterKey(_ character: String) -> some View {
        Button {
            insertCharacter(character)
        } label: {
            Text(isShifted ? character.uppercased() : character)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 47)
                .background(keyBackground, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(KeyboardPressStyle())
        .contextMenu {
            ForEach(alternatives(for: character), id: \.self) { alternative in
                Button(isShifted ? alternative.uppercased() : alternative) {
                    insertCharacter(alternative)
                }
            }
        }
        .accessibilityHint(alternatives(for: character).isEmpty ? "" : "Mantén pulsado para ver más caracteres")
    }

    private func insertCharacter(_ character: String) {
        insertText(isShifted ? character.uppercased() : character)
        if isShifted { isShifted = false }
    }

    private func alternatives(for character: String) -> [String] {
        switch character {
        case "a": ["á"]
        case "e": ["é"]
        case "i": ["í"]
        case "o": ["ó"]
        case "u": ["ú", "ü"]
        case "!": ["¡"]
        case "?": ["¿"]
        case "(": ["["]
        case ")": ["]"]
        case "<": [">"]
        case "+": ["="]
        default: []
        }
    }

    private func specialKey(
        _ symbol: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: width, height: 47)
                .background(specialBackground, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(KeyboardPressStyle())
    }

    private func textSpecialKey(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .frame(width: width, height: 47)
                .background(specialBackground, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(KeyboardPressStyle())
    }

    private var clipboardPanel: some View {
        VStack(spacing: 7) {
            sectionSelector
            if !model.hasFullAccess { fullAccessBanner }
            clipList
            clipboardControls
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
    }

    private var sectionSelector: some View {
        HStack(spacing: 2) {
            ForEach(KeyboardSection.allCases) { item in
                Button {
                    section = item
                    refresh()
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            section == item ? Color.white.opacity(0.28) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(specialBackground, in: RoundedRectangle(cornerRadius: 9))
    }

    private var fullAccessBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
            Text("Activa “Acceso total” para leer tus copias").font(.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var clipList: some View {
        if section == .temporary {
            if model.temporaryClips.isEmpty {
                emptyState(
                    title: model.hasFullAccess ? "Copia texto para verlo aquí" : "Acceso total desactivado",
                    symbol: model.hasFullAccess ? "clipboard" : "lock.fill"
                )
            } else {
                temporaryList
            }
        } else if model.savedClips.isEmpty {
            emptyState(title: "No hay elementos guardados", symbol: "pin")
        } else {
            savedList
        }
    }

    private func emptyState(title: String, symbol: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text(title).font(.headline).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var temporaryList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(model.temporaryClips) { clip in
                    clipRow(
                        text: clip.text,
                        date: clip.capturedAt,
                        symbol: symbol(for: clip.kindRawValue),
                        accentColor: .orange,
                        primaryAction: { insertTemporary(clip) },
                        secondarySymbol: "pin.fill",
                        secondaryAction: { saveTemporary(clip) }
                    )
                }
            }
        }
    }

    private var savedList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(model.savedClips) { clip in
                    clipRow(
                        text: clip.text,
                        date: clip.updatedAt,
                        symbol: clip.kindSymbol,
                        accentColor: accent,
                        primaryAction: { insertSaved(clip) },
                        secondarySymbol: clip.isFavorite ? "star.fill" : "star",
                        secondaryAction: { toggleFavorite(clip) }
                    )
                }
            }
        }
    }

    private func clipRow(
        text: String,
        date: Date,
        symbol: String,
        accentColor: Color,
        primaryAction: @escaping () -> Void,
        secondarySymbol: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                HStack(spacing: 9) {
                    Image(systemName: symbol).foregroundStyle(accentColor).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text)
                            .font(.callout)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: secondaryAction) {
                Image(systemName: secondarySymbol)
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(keyBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
    }

    private var clipboardControls: some View {
        HStack(spacing: 6) {
            specialKey("globe", width: 52, action: nextKeyboard)
            specialKey("doc.on.clipboard", width: 52, action: paste)
                .disabled(!model.hasFullAccess)
                .opacity(model.hasFullAccess ? 1 : 0.4)
            specialKey("delete.left", width: 52, action: delete)
            Button(action: insertSpace) {
                Text("espacio")
                    .frame(maxWidth: .infinity, minHeight: 47)
                    .background(accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(KeyboardPressStyle())
            specialKey("return", width: 72, action: insertReturn)
        }
    }

    private func symbol(for kindRawValue: String) -> String {
        switch kindRawValue {
        case "link": "link"
        case "email": "envelope"
        case "phone": "phone"
        case "image": "photo"
        default: "text.alignleft"
        }
    }
}

private struct KeyboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

