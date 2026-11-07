import Combine
import SwiftUI
import UIKit

/// Barra de sugerencias mientras se escribe, en UIKit. Antes era SwiftUI y se redibujaba tras cada
/// tecla: en iOS 27 SwiftUI va más lento y, al teclear deprisa, esos redibujados se acumulaban y
/// retrasaban la siguiente pulsación. Gboard y el teclado de Apple tampoco usan SwiftUI aquí.
final class SuggestionBarUIView: UIView {
    private enum Mode {
        case glide
        case tools
        case quickPaste
        case suggestions
    }

    private let engine: KeyboardEngine
    private var palette: KeyboardPalette?
    private var colors = KeyGridColors(KeyboardPalette.make(theme: .dark, systemIsDark: true))
    private var observers: Set<AnyCancellable> = []
    private var refreshScheduled = false
    private var mode: Mode = .tools

    private let toggleButton = BarIconButton()
    private let toolButtons: [BarIconButton]
    private let compactButtons: [BarIconButton]
    private let slotButtons: [BarTextButton]
    private let separators: [UIView]
    private let chip = QuickPasteChip()
    private let glideLabel = UILabel()
    private let speedLabel = UILabel()
    private var slots: [SuggestionItem?] = []

    init(engine: KeyboardEngine) {
        self.engine = engine
        toolButtons = (0..<7).map { _ in BarIconButton() }
        compactButtons = (0..<2).map { _ in BarIconButton() }
        slotButtons = (0..<3).map { _ in BarTextButton() }
        separators = (0..<2).map { _ in UIView() }
        super.init(frame: .zero)
        backgroundColor = .clear

        toggleButton.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
        toggleButton.onTap = { [weak self] in self?.engine.showsToolbar.toggle() }
        addSubview(toggleButton)

        let tools: [(String, String, (KeyboardEngine) -> Void)] = [
            ("face.smiling", "Emojis", { $0.open(.emoji) }),
            ("clipboard", "Portapapeles", { $0.open(.clipboard) }),
            ("character.cursor.ibeam", "Edición de texto", { $0.open(.editing) }),
            ("hand.point.up.left", "Modo una mano", { $0.toggleOneHandedMode() }),
            ("paintpalette", "Temas", { $0.open(.themes) }),
            ("gearshape", "Ajustes del teclado", { $0.open(.settings) }),
            ("keyboard.chevron.compact.down", "Ocultar teclado", { $0.dismissKeyboard() })
        ]
        for (button, tool) in zip(toolButtons, tools) {
            button.symbol = tool.0
            button.accessibilityLabel = tool.1
            button.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
            button.onTap = { [weak self] in
                guard let self else { return }
                tool.2(self.engine)
            }
            addSubview(button)
        }
        let compact: [(String, String, (KeyboardEngine) -> Void)] = [
            ("clipboard", "Portapapeles", { $0.open(.clipboard) }),
            ("keyboard.chevron.compact.down", "Ocultar teclado", { $0.dismissKeyboard() })
        ]
        for (button, tool) in zip(compactButtons, compact) {
            button.symbol = tool.0
            button.accessibilityLabel = tool.1
            button.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
            button.onTap = { [weak self] in
                guard let self else { return }
                tool.2(self.engine)
            }
            addSubview(button)
        }

        for (index, button) in slotButtons.enumerated() {
            button.onDown = { [weak self] in self?.engine.keyFeedback(.character) }
            button.onTap = { [weak self] in
                guard let self, self.slots.indices.contains(index), let item = self.slots[index] else { return }
                self.engine.selectSuggestion(item)
            }
            addSubview(button)
        }
        separators.forEach(addSubview)

        chip.onDown = { [weak self] in self?.engine.keyFeedback(.character) }
        chip.onTap = { [weak self] in self?.engine.useQuickPaste() }
        chip.accessibilityLabel = "Pegar lo último copiado"
        addSubview(chip)

        glideLabel.textAlignment = .center
        glideLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        glideLabel.adjustsFontSizeToFitWidth = true
        glideLabel.minimumScaleFactor = 0.6
        addSubview(glideLabel)

        speedLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        speedLabel.textAlignment = .right
        speedLabel.isUserInteractionEnabled = false
        speedLabel.isAccessibilityElement = false
        addSubview(speedLabel)

        engine.bar.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &observers)
        engine.glideTrail.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &observers)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    // MARK: Contenido

    func apply(palette: KeyboardPalette) {
        if palette != self.palette {
            self.palette = palette
            colors = KeyGridColors(palette)
            let separatorColor = UIColor(palette.separator)
            separators.forEach { $0.backgroundColor = separatorColor }
            chip.apply(background: UIColor(palette.chip), text: colors.text, secondary: colors.secondaryText)
            glideLabel.textColor = colors.accent
            speedLabel.textColor = colors.secondaryText
        }
        refresh()
    }

    /// Los cambios llegan antes de aplicarse (`objectWillChange`): se pinta en el siguiente turno.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    func refresh() {
        let bar = engine.bar
        let quickPaste = engine.currentWord.isEmpty ? bar.quickPaste : nil
        let hasContent = bar.suggestions.contains { $0 != nil } || quickPaste != nil

        toggleButton.isHidden = !hasContent
        toggleButton.symbol = bar.showsToolbar ? "chevron.left" : "square.grid.2x2"
        toggleButton.accessibilityLabel = bar.showsToolbar ? "Ver sugerencias" : "Ver herramientas"

        if engine.isGliding {
            mode = .glide
            glideLabel.text = engine.glideTrail.preview ?? ""
        } else if bar.showsToolbar || !hasContent {
            mode = .tools
        } else if let quickPaste {
            mode = .quickPaste
            chip.configure(with: quickPaste)
        } else {
            mode = .suggestions
            configureSlots(bar.suggestions)
        }

        // Herramientas activas (una mano, incógnito) en el color de acento.
        for (index, button) in toolButtons.enumerated() {
            let active = (index == 3 && engine.preferences.oneHandedMode != .off)
                || (index == 5 && engine.preferences.incognito)
            button.apply(color: active ? colors.accent : colors.text.withAlphaComponent(0.85))
        }
        compactButtons.forEach { $0.apply(color: colors.text.withAlphaComponent(0.85)) }
        toggleButton.apply(color: colors.text.withAlphaComponent(0.85))

        glideLabel.isHidden = mode != .glide
        toolButtons.forEach { $0.isHidden = mode != .tools }
        compactButtons.forEach { $0.isHidden = mode != .quickPaste }
        chip.isHidden = mode != .quickPaste
        let visibleSlots = mode == .suggestions ? slots.count : 0
        for (index, button) in slotButtons.enumerated() { button.isHidden = index >= visibleSlots }
        for (index, separator) in separators.enumerated() { separator.isHidden = index + 1 >= visibleSlots }

        updateSpeedLine()
        setNeedsLayout()
    }

    private func configureSlots(_ suggestions: [SuggestionItem?]) {
        slots = Array(suggestions.prefix(3))
        let hasCorrection = slots.contains { $0?.kind == .correction }
        for (index, button) in slotButtons.enumerated() {
            guard index < slots.count, let item = slots[index] else {
                button.setTitle(nil, font: .systemFont(ofSize: 17), color: colors.text)
                button.isEnabled = false
                continue
            }
            let title = item.kind == .typed && hasCorrection ? "«\(item.text)»" : item.text
            let font: UIFont = item.kind == .emoji
                ? .systemFont(ofSize: 22)
                : .systemFont(ofSize: 17, weight: item.kind == .correction ? .semibold : .regular)
            button.setTitle(title, font: font, color: item.kind == .correction ? colors.accent : colors.text)
            button.isEnabled = true
            button.accessibilityLabel = item.text
        }
    }

    /// Línea pequeña con la velocidad (opcional, en ⚙︎): para hacer una captura justo al fallar.
    private func updateSpeedLine() {
        guard engine.preferences.showSpeed else {
            speedLabel.isHidden = true
            return
        }
        let diagnostics = engine.touchDiagnostics
        func pair(_ samples: [Double]) -> String {
            guard !samples.isEmpty else { return "–" }
            let average = samples.reduce(0, +) / Double(samples.count)
            return String(format: "%.0f/%.0f", average, samples.max() ?? 0)
        }
        speedLabel.text = "iOS \(pair(diagnostics.delivery)) · teclado \(pair(diagnostics.handling)) · hilo \(pair(diagnostics.lateness)) ms · bloqueos \(diagnostics.stalls)"
        speedLabel.isHidden = false
    }

    // MARK: Colocación

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        var x: CGFloat = 4
        if !toggleButton.isHidden {
            toggleButton.frame = CGRect(x: x, y: 0, width: 44, height: height)
            x += 44
        }
        let width = max(0, bounds.width - 4 - x)

        switch mode {
        case .glide:
            glideLabel.frame = CGRect(x: x, y: 0, width: width, height: height)
        case .tools:
            let count = CGFloat(toolButtons.count)
            let buttonWidth = min(44, width / count)
            let spacing = count > 1 ? (width - buttonWidth * count) / (count - 1) : 0
            for (index, button) in toolButtons.enumerated() {
                button.frame = CGRect(x: x + CGFloat(index) * (buttonWidth + spacing), y: 0, width: buttonWidth, height: height)
            }
        case .quickPaste:
            let compactWidth: CGFloat = 44 * CGFloat(compactButtons.count)
            let chipWidth = min(230, max(0, width - compactWidth - 4))
            chip.frame = CGRect(x: x, y: (height - 32) / 2, width: chipWidth, height: 32)
            for (index, button) in compactButtons.enumerated() {
                button.frame = CGRect(x: bounds.width - 4 - compactWidth + CGFloat(index) * 44, y: 0, width: 44, height: height)
            }
        case .suggestions:
            let count = CGFloat(max(slots.count, 1))
            let slotWidth = (width - (count - 1)) / count
            for (index, button) in slotButtons.enumerated() where index < slots.count {
                button.frame = CGRect(x: x + CGFloat(index) * (slotWidth + 1), y: 0, width: slotWidth, height: height)
            }
            for (index, separator) in separators.enumerated() {
                separator.frame = CGRect(x: x + CGFloat(index + 1) * (slotWidth + 1) - 1, y: (height - 20) / 2, width: 1, height: 20)
            }
        }
        speedLabel.frame = CGRect(x: 4, y: height - 11, width: bounds.width - 8, height: 11)
    }
}

/// Botón de icono de la barra: vibra al tocar y actúa al levantar el dedo dentro.
final class BarIconButton: UIControl {
    var onDown: () -> Void = {}
    var onTap: () -> Void = {}
    var symbol = "" {
        didSet {
            guard symbol != oldValue else { return }
            imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        }
    }
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .center
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(released), for: .touchUpInside)
        addTarget(self, action: #selector(abandoned), for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    func apply(color: UIColor) {
        if imageView.tintColor != color { imageView.tintColor = color }
    }

    @objc private func pressed() {
        alpha = 0.55
        onDown()
    }

    @objc private func released() {
        alpha = 1
        onTap()
    }

    @objc private func abandoned() {
        alpha = 1
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }
}

/// Hueco de una sugerencia.
final class BarTextButton: UIControl {
    var onDown: () -> Void = {}
    var onTap: () -> Void = {}
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(released), for: .touchUpInside)
        addTarget(self, action: #selector(abandoned), for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 4, dy: 0)
    }

    func setTitle(_ title: String?, font: UIFont, color: UIColor) {
        if label.text != title { label.text = title }
        if label.font != font { label.font = font }
        if label.textColor != color { label.textColor = color }
    }

    @objc private func pressed() {
        guard isEnabled else { return }
        alpha = 0.55
        onDown()
    }

    @objc private func released() {
        alpha = 1
        guard isEnabled else { return }
        onTap()
    }

    @objc private func abandoned() {
        alpha = 1
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        onTap()
        return true
    }
}

/// Chip de pegado rápido con lo último copiado.
final class QuickPasteChip: UIControl {
    var onDown: () -> Void = {}
    var onTap: () -> Void = {}
    private let iconView = UIImageView()
    private let label = UILabel()
    private var showsThumbnail = false
    private var configuredKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 5
        iconView.isUserInteractionEnabled = false
        label.font = .systemFont(ofSize: 15)
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        addSubview(iconView)
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(released), for: .touchUpInside)
        addTarget(self, action: #selector(abandoned), for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(background: UIColor, text: UIColor, secondary: UIColor) {
        backgroundColor = background
        label.textColor = text
        iconView.tintColor = text
    }

    func configure(with clip: KeyboardClip) {
        let key = "\(clip.imageFileName ?? "")|\(clip.isSensitive)|\(clip.text)"
        guard key != configuredKey else { return }
        configuredKey = key
        if let fileName = clip.imageFileName {
            showsThumbnail = true
            iconView.contentMode = .scaleAspectFill
            iconView.image = ClipThumbnailCache.thumbnail(for: fileName)
            label.text = "Imagen copiada"
        } else {
            showsThumbnail = false
            iconView.contentMode = .center
            let symbol = clip.isSensitive ? "lock.fill" : "doc.on.clipboard"
            iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15))
            label.text = clip.isSensitive ? "Pegar contenido privado" : clip.text.replacingOccurrences(of: "\n", with: " ")
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let iconSize: CGFloat = showsThumbnail ? 26 : 18
        iconView.frame = CGRect(x: 12, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        let labelX = iconView.frame.maxX + 7
        label.frame = CGRect(x: labelX, y: 0, width: max(0, bounds.width - labelX - 12), height: bounds.height)
    }

    @objc private func pressed() {
        alpha = 0.55
        onDown()
    }

    @objc private func released() {
        alpha = 1
        onTap()
    }

    @objc private func abandoned() {
        alpha = 1
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }
}

/// Aviso breve sobre la barra («Copiado», «Borrado · Deshacer»…). Antes era SwiftUI; en UIKit no
/// obliga a redibujar la vista SwiftUI del teclado al aparecer o desaparecer.
final class KeyboardToastView: UIView {
    var onAction: () -> Void = {}
    private let label = UILabel()
    private let actionButton = UIButton(type: .custom)
    private var message: String?
    private var actionTitle: String?
    private var palette: KeyboardPalette?
    private static let padding = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    private static let spacing: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        actionButton.contentHorizontalAlignment = .right
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        addSubview(actionButton)
        isHidden = true
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    var isShowing: Bool { message != nil }

    func show(message newMessage: String?, actionTitle newActionTitle: String?, palette newPalette: KeyboardPalette) {
        guard newMessage != nil || message != nil else { return }
        if newPalette != palette || newActionTitle != actionTitle {
            palette = newPalette
            actionTitle = newActionTitle
            let accentText = UIColor(newPalette.accentText)
            backgroundColor = UIColor(newPalette.accent)
            label.textColor = accentText
            if let newActionTitle {
                actionButton.setAttributedTitle(NSAttributedString(string: newActionTitle, attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: accentText,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]), for: .normal)
                actionButton.accessibilityLabel = newActionTitle
            }
            actionButton.isHidden = newActionTitle == nil
        }
        // Sin acción, los toques pasan a la barra de debajo.
        isUserInteractionEnabled = newActionTitle != nil
        if let newMessage, label.text != newMessage { label.text = newMessage }

        let wasShowing = message != nil
        message = newMessage
        if newMessage != nil, !wasShowing {
            layer.removeAllAnimations()
            isHidden = false
            alpha = 0
            transform = CGAffineTransform(translationX: 0, y: -6)
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.alpha = 1
                self.transform = .identity
            }
        } else if newMessage == nil, wasShowing {
            // Con transparencia 0, iOS ya no le manda toques.
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
                self.alpha = 0
            }
        }
        setNeedsLayout()
    }

    private func actionSize(maxWidth: CGFloat) -> CGSize {
        guard !actionButton.isHidden else { return .zero }
        let size = actionButton.sizeThatFits(CGSize(width: maxWidth, height: 40))
        return CGSize(width: min(ceil(size.width), maxWidth), height: ceil(size.height))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let padding = Self.padding
        let maxContent = max(0, size.width - padding.left - padding.right)
        let action = actionSize(maxWidth: maxContent / 2)
        let actionWidth = action.width > 0 ? action.width + Self.spacing : 0
        let text = label.sizeThatFits(CGSize(width: max(0, maxContent - actionWidth), height: .greatestFiniteMagnitude))
        let width = min(ceil(text.width) + actionWidth, maxContent) + padding.left + padding.right
        let height = max(ceil(text.height), action.height) + padding.top + padding.bottom
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        let content = bounds.inset(by: Self.padding)
        let action = actionSize(maxWidth: content.width / 2)
        let actionWidth = action.width > 0 ? action.width + Self.spacing : 0
        label.frame = CGRect(x: content.minX, y: content.minY, width: max(0, content.width - actionWidth), height: content.height)
        // El botón ocupa todo el alto del aviso, para acertar fácil.
        actionButton.frame = CGRect(
            x: label.frame.maxX,
            y: 0,
            width: max(0, content.maxX - label.frame.maxX),
            height: bounds.height
        )
    }

    @objc private func actionTapped() {
        onAction()
    }
}
