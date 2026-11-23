import SwiftUI
import UIKit

/// Retraso de la pulsación larga elegible en el panel de ajustes del teclado.
private enum SettingsLongPressOption: Int, CaseIterable {
    case short = 250
    case normal = 400
    case long = 550

    init(milliseconds: Int) {
        self = Self.allCases.min { abs($0.rawValue - milliseconds) < abs($1.rawValue - milliseconds) } ?? .normal
    }

    var milliseconds: Int { rawValue }

    var title: String {
        switch self {
        case .short: "Corta"
        case .normal: "Normal"
        case .long: "Larga"
        }
    }
}

/// Panel de ajustes del teclado en UIKit puro (sin `UIHostingController` ni SwiftUI):
/// cabecera, scroll rápido propio, interruptores, deslizador, chips y diagnóstico son controles
/// nativos de UIKit, evitando los conflictos táctiles de SwiftUI dentro de una extensión.
@MainActor
final class KeyboardSettingsPanelUIView: UIView {
    private let engine: KeyboardEngine
    private var appliedPalette: KeyboardPalette?
    private var headerHeight: CGFloat = 44
    private var contentInsets: UIEdgeInsets = .zero
    private let touchScope = KeyboardScrollTouchScope()

    let headerView = UIView()
    let backButton = SettingsBackButton()
    private let headerTitleLabel = UILabel()

    let scrollView = KeyboardPanelUIScrollView()
    private let contentStack = UIStackView()
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private var contentWidthConstraint: NSLayoutConstraint?

    // Estado
    private let statusCard = UIView()
    private let statusStack = UIStackView()
    private let fullAccessRow = SettingsStatusRow()
    private let appGroupRow = SettingsStatusRow()
    private let safeModeRow = SettingsStatusRow()
    private let speedSummaryLabel = UILabel()
    private let copyReportButton = SettingsActionButton(title: "Copiar informe de velocidad", symbol: "doc.on.doc")

    // Cabeceras y textos auxiliares (para aplicar colores de paleta)
    private var sectionHeaders: [UILabel] = []
    private var primaryLabels: [UILabel] = []
    private var secondaryLabels: [UILabel] = []

    // Vibración
    let hapticsSwitchRow = SettingsSwitchRow(title: "Vibrar al pulsar")
    private let hapticsDetailsStack = UIStackView()
    let hapticStyleChips = SettingsChipBar(titles: HapticStyleOption.allCases.map(\.title))
    private let strengthTitleLabel = UILabel()
    let strengthSlider = UISlider()
    private let strengthValueLabel = UILabel()

    // Sonido
    private let soundSwitchRow = SettingsSwitchRow(title: "Sonido al pulsar")
    private let soundStyleChips = SettingsChipBar(titles: KeySoundStyle.allCases.map(\.title))

    // Escritura
    private let glideSwitchRow = SettingsSwitchRow(title: "Escritura deslizando")
    let autocorrectSwitchRow = SettingsSwitchRow(title: "Autocorrección")
    private let spaceAfterSuggestionRow = SettingsSwitchRow(title: "Espacio tras elegir una sugerencia")
    private let smartTouchRow = SettingsSwitchRow(title: "Precisión inteligente")
    private let longPressSymbolsSwitchRow = SettingsSwitchRow(title: "Símbolos al mantener pulsado")
    let longPressChips = SettingsChipBar(titles: SettingsLongPressOption.allCases.map(\.title))
    private let numberRowSwitchRow = SettingsSwitchRow(title: "Fila de números")
    private let keyBordersSwitchRow = SettingsSwitchRow(title: "Bordes de las teclas")
    private let incognitoSwitchRow = SettingsSwitchRow(title: "Modo incógnito")

    // Diccionario personal
    let addWordButton = SettingsActionButton(title: "Añadir palabra al diccionario", symbol: "plus.circle.fill")
    private let dictionarySummaryLabel = UILabel()
    private let savedWordsBar = SettingsWordChipsBar()
    private let clearDictionaryButton = SettingsActionButton(title: "Borrar palabras aprendidas", symbol: "trash")

    // Diagnóstico
    private let showSpeedRow = SettingsSwitchRow(title: "Mostrar velocidad en la barra")
    private let deliveryRow = SettingsTimingRow(title: "Retraso de iOS al entregar el toque")
    private let handlingRow = SettingsTimingRow(title: "Tiempo del teclado por toque")
    private let feedbackRow = SettingsTimingRow(title: "Vibración (lo que tarda iOS en aceptarla)")
    private let latenessRow = SettingsTimingRow(title: "Retraso del hilo principal")
    private let stallsRow = SettingsTimingRow(title: "Bloqueos de más de 100 ms")
    private let touchesRow = SettingsCounterRow(title: "Toques")
    private let typedRow = SettingsCounterRow(title: "Escritos")
    private let rolloversRow = SettingsCounterRow(title: "Escritos al tocar con otro dedo")
    private let cancelledTypedRow = SettingsCounterRow(title: "Cancelados por iOS y escritos")
    private let cancelledLostRow = SettingsCounterRow(title: "Cancelados por iOS y perdidos")
    private let unfinishedRow = SettingsCounterRow(title: "Sin aviso de fin (escritos)")
    private let ignoredRow = SettingsCounterRow(title: "Ignorados (deslizando o dedo apoyado)")
    private let glidesRow = SettingsCounterRow(title: "Deslizamientos")
    private let glidesAsTapsRow = SettingsCounterRow(title: "Deslizamientos que eran toques")
    private let cursorSwipesRow = SettingsCounterRow(title: "Cursor con la barra espaciadora")
    private let alternatesRow = SettingsCounterRow(title: "Pulsaciones largas")
    private let smartChoicesRow = SettingsCounterRow(title: "Elegidos por la precisión inteligente")
    private let recentTitleLabel = UILabel()
    private let recentBodyLabel = UILabel()
    private let resetDiagnosticsButton = SettingsActionButton(title: "Poner a cero", symbol: nil)

    private var timingRows: [SettingsTimingRow] {
        [deliveryRow, handlingRow, feedbackRow, latenessRow, stallsRow]
    }

    private var counterRows: [SettingsCounterRow] {
        [
            touchesRow, typedRow, rolloversRow, cancelledTypedRow, cancelledLostRow,
            unfinishedRow, ignoredRow, glidesRow, glidesAsTapsRow, cursorSwipesRow,
            alternatesRow, smartChoicesRow
        ]
    }

    private var switchRows: [SettingsSwitchRow] {
        [
            hapticsSwitchRow, soundSwitchRow, glideSwitchRow, autocorrectSwitchRow,
            spaceAfterSuggestionRow, smartTouchRow, longPressSymbolsSwitchRow,
            numberRowSwitchRow, keyBordersSwitchRow, incognitoSwitchRow, showSpeedRow
        ]
    }

    init(engine: KeyboardEngine) {
        self.engine = engine
        super.init(frame: .zero)
        // Alfa mínimo para garantizar hit-testing continuo incluso en el tema Cristal (fondo claro).
        backgroundColor = UIColor(white: 0, alpha: 0.01)
        setupHeader()
        setupScrollAndSections()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    // MARK: Construcción

    private func setupHeader() {
        headerView.backgroundColor = .clear
        addSubview(headerView)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        headerTitleLabel.text = "Ajustes"
        headerTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerTitleLabel)
        primaryLabels.append(headerTitleLabel)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.heightAnchor.constraint(equalToConstant: 34),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            headerTitleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            headerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -10),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupScrollAndSections() {
        scrollView.backgroundColor = UIColor(white: 0, alpha: 0.01)
        // Igual que Ajustes de iOS: retrasar el toque a los controles permite que cualquier
        // arrastre vertical sobre interruptores, chips o deslizador desplace la lista sin trabarse,
        // mientras que un toque rápido se entrega al instante al levantar el dedo.
        scrollView.delaysContentTouches = true
        scrollView.canCancelContentTouches = true
        scrollView.decelerationRate = .fast
        scrollView.alwaysBounceVertical = true
        scrollView.isDirectionalLockEnabled = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        addSubview(scrollView)
        touchScope.attach(to: scrollView, disableContentTouchDelay: false)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let leading = contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12)
        let trailing = contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12)
        let bottom = contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -14)
        let width = contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24)
        contentLeadingConstraint = leading
        contentTrailingConstraint = trailing
        contentBottomConstraint = bottom
        contentWidthConstraint = width

        NSLayoutConstraint.activate([
            leading,
            trailing,
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            bottom,
            width
        ])

        buildStatusCard()
        buildVibrationSection()
        buildSoundSection()
        buildWritingSection()
        buildDictionarySection()
        buildDiagnosticsSection()
    }

    private func buildStatusCard() {
        statusCard.layer.cornerRadius = 12
        statusCard.layer.cornerCurve = .continuous

        statusStack.axis = .vertical
        statusStack.spacing = 6
        statusStack.alignment = .fill
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusStack)

        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 10),
            statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -10),
            statusStack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 10),
            statusStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -10)
        ])

        speedSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        speedSummaryLabel.numberOfLines = 0
        secondaryLabels.append(speedSummaryLabel)

        statusStack.addArrangedSubview(fullAccessRow)
        statusStack.addArrangedSubview(appGroupRow)
        statusStack.addArrangedSubview(safeModeRow)
        statusStack.addArrangedSubview(speedSummaryLabel)
        statusStack.addArrangedSubview(copyReportButton)
        contentStack.addArrangedSubview(statusCard)
    }

    private func buildVibrationSection() {
        let section = makeSection(title: "Vibración")
        section.addArrangedSubview(hapticsSwitchRow)

        hapticsDetailsStack.axis = .vertical
        hapticsDetailsStack.spacing = 8
        hapticsDetailsStack.alignment = .fill
        hapticsDetailsStack.addArrangedSubview(hapticStyleChips)

        let sliderRow = UIStackView()
        sliderRow.axis = .horizontal
        sliderRow.spacing = 10
        sliderRow.alignment = .center

        strengthTitleLabel.text = "Intensidad"
        strengthTitleLabel.font = .systemFont(ofSize: 13)
        strengthTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        primaryLabels.append(strengthTitleLabel)

        strengthSlider.minimumValue = 0.1
        strengthSlider.maximumValue = 1.0
        strengthSlider.isContinuous = true
        strengthSlider.accessibilityLabel = "Intensidad de la vibración"

        strengthValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        strengthValueLabel.textAlignment = .right
        strengthValueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        secondaryLabels.append(strengthValueLabel)

        sliderRow.addArrangedSubview(strengthTitleLabel)
        sliderRow.addArrangedSubview(strengthSlider)
        sliderRow.addArrangedSubview(strengthValueLabel)
        hapticsDetailsStack.addArrangedSubview(sliderRow)

        section.addArrangedSubview(hapticsDetailsStack)
        contentStack.addArrangedSubview(section)
    }

    private func buildSoundSection() {
        let section = makeSection(title: "Sonido")
        section.addArrangedSubview(soundSwitchRow)
        section.addArrangedSubview(soundStyleChips)
        contentStack.addArrangedSubview(section)
    }

    private func buildWritingSection() {
        let section = makeSection(title: "Escritura")
        section.addArrangedSubview(glideSwitchRow)
        section.addArrangedSubview(autocorrectSwitchRow)
        section.addArrangedSubview(spaceAfterSuggestionRow)
        section.addArrangedSubview(smartTouchRow)

        let smartCaption = makeCaption(
            "Si tocas justo entre dos letras, elige la que forma una palabra, como el teclado de Apple."
        )
        section.addArrangedSubview(smartCaption)

        section.addArrangedSubview(longPressSymbolsSwitchRow)

        let longPressLabel = UILabel()
        longPressLabel.text = "Pulsación larga (acentos y símbolos)"
        longPressLabel.font = .systemFont(ofSize: 13)
        primaryLabels.append(longPressLabel)
        section.addArrangedSubview(longPressLabel)
        section.addArrangedSubview(longPressChips)

        section.addArrangedSubview(numberRowSwitchRow)
        section.addArrangedSubview(keyBordersSwitchRow)
        section.addArrangedSubview(incognitoSwitchRow)
        contentStack.addArrangedSubview(section)
    }

    private func buildDictionarySection() {
        let section = makeSection(title: "Diccionario personal")
        section.addArrangedSubview(addWordButton)

        dictionarySummaryLabel.font = .systemFont(ofSize: 11)
        dictionarySummaryLabel.numberOfLines = 0
        secondaryLabels.append(dictionarySummaryLabel)
        section.addArrangedSubview(dictionarySummaryLabel)

        section.addArrangedSubview(savedWordsBar)
        section.addArrangedSubview(clearDictionaryButton)
        contentStack.addArrangedSubview(section)
    }

    private func buildDiagnosticsSection() {
        let section = makeSection(title: "Diagnóstico de toques")
        section.addArrangedSubview(showSpeedRow)

        let metricsStack = UIStackView()
        metricsStack.axis = .vertical
        metricsStack.spacing = 4
        metricsStack.alignment = .fill
        timingRows.forEach { metricsStack.addArrangedSubview($0) }
        counterRows.forEach { metricsStack.addArrangedSubview($0) }
        section.addArrangedSubview(metricsStack)

        recentTitleLabel.text = "Últimos toques"
        recentTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        secondaryLabels.append(recentTitleLabel)
        section.addArrangedSubview(recentTitleLabel)

        recentBodyLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        recentBodyLabel.numberOfLines = 0
        primaryLabels.append(recentBodyLabel)
        section.addArrangedSubview(recentBodyLabel)

        section.addArrangedSubview(resetDiagnosticsButton)
        section.addArrangedSubview(makeCaption(
            "Si notas que falla una tecla, abre esto justo después y pulsa «Copiar informe de velocidad» (arriba): pégalo en tu mensaje."
        ))
        contentStack.addArrangedSubview(section)
    }

    private func makeSection(title: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill

        let header = UILabel()
        header.text = title
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        sectionHeaders.append(header)
        stack.addArrangedSubview(header)
        return stack
    }

    private func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11)
        label.numberOfLines = 0
        secondaryLabels.append(label)
        return label
    }

    // MARK: Acciones

    private func wireActions() {
        backButton.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
        backButton.onTap = { [weak self] in self?.engine.closePanel() }

        copyReportButton.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
        copyReportButton.onTap = { [weak self] in self?.engine.copyDiagnosticsReport() }

        hapticsSwitchRow.onChange = { [weak self] value in
            guard let self else { return }
            self.engine.updatePreferences { $0.haptics = value }
            if value { self.engine.previewHaptic() }
        }
        hapticStyleChips.onSelect = { [weak self] index in
            guard let self, HapticStyleOption.allCases.indices.contains(index) else { return }
            let style = HapticStyleOption.allCases[index]
            self.engine.updatePreferences { $0.hapticsStyle = style }
            self.engine.previewHaptic()
        }
        strengthSlider.addTarget(self, action: #selector(strengthChanged), for: .valueChanged)
        strengthSlider.addTarget(self, action: #selector(strengthFinished), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        soundSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.sound = value }
        }
        soundStyleChips.onSelect = { [weak self] index in
            guard let self, KeySoundStyle.allCases.indices.contains(index) else { return }
            let style = KeySoundStyle.allCases[index]
            self.engine.updatePreferences { $0.soundStyle = style }
            self.engine.keyFeedback(.character)
        }

        glideSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.glideTyping = value }
        }
        autocorrectSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.autocorrect = value }
        }
        spaceAfterSuggestionRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.spaceAfterSuggestion = value }
        }
        smartTouchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.smartTouch = value }
        }
        longPressSymbolsSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.longPressSymbols = value }
        }
        longPressChips.onSelect = { [weak self] index in
            guard let self, SettingsLongPressOption.allCases.indices.contains(index) else { return }
            let option = SettingsLongPressOption.allCases[index]
            self.engine.updatePreferences { $0.longPressDelay = option.milliseconds }
        }
        numberRowSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.numberRow = value }
        }
        keyBordersSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.keyBorders = value }
        }
        incognitoSwitchRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.incognito = value }
        }
        showSpeedRow.onChange = { [weak self] value in
            self?.engine.updatePreferences { $0.showSpeed = value }
        }

        addWordButton.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
        addWordButton.onTap = { [weak self] in self?.engine.openAddWord() }

        savedWordsBar.onRemove = { [weak self] word in
            guard let self else { return }
            self.engine.keyFeedback(.delete)
            self.engine.removePersonalWord(word)
            self.refreshPersonalDictionary()
        }

        clearDictionaryButton.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
        clearDictionaryButton.onTap = { [weak self] in
            guard let self else { return }
            self.engine.clearPersonalDictionary()
            self.refreshPersonalDictionary()
        }

        resetDiagnosticsButton.onDown = { [weak self] in self?.engine.keyFeedback(.modifier) }
        resetDiagnosticsButton.onTap = { [weak self] in
            guard let self else { return }
            self.engine.touchDiagnostics = TouchDiagnostics()
            KeyboardPanelTouchDiagnostics.shared.reset()
            self.refreshDiagnostics()
        }
    }

    @objc private func strengthChanged() {
        let snapped = snappedStrength(Double(strengthSlider.value))
        strengthValueLabel.text = "\(Int((snapped * 100).rounded())) %"
    }

    @objc private func strengthFinished() {
        let snapped = snappedStrength(Double(strengthSlider.value))
        strengthSlider.value = Float(snapped)
        strengthValueLabel.text = "\(Int((snapped * 100).rounded())) %"
        engine.updatePreferences { $0.hapticsStrength = snapped }
        engine.previewHaptic()
    }

    private func snappedStrength(_ raw: Double) -> Double {
        let clamped = min(max(raw, 0.1), 1.0)
        return (clamped * 20).rounded() / 20
    }

    // MARK: Diseño y actualización

    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.withoutAnimation {
            let width = bounds.width
            let topOffset = contentInsets.top
            let availableHeight = max(0, bounds.height - topOffset)
            let topHeight = min(headerHeight, availableHeight)
            let headerFrame = CGRect(
                x: contentInsets.left,
                y: topOffset,
                width: max(0, width - contentInsets.left - contentInsets.right),
                height: topHeight
            )
            if headerView.frame != headerFrame { headerView.frame = headerFrame }
            let scrollTop = topOffset + topHeight
            let scrollFrame = CGRect(x: 0, y: scrollTop, width: width, height: max(0, bounds.height - scrollTop))
            if scrollView.frame != scrollFrame { scrollView.frame = scrollFrame }
        }
    }

    func apply(palette: KeyboardPalette, stripHeight: CGFloat, safeAreaInsets: UIEdgeInsets = .zero) {
        if abs(headerHeight - stripHeight) > 0.5 || contentInsets != safeAreaInsets {
            headerHeight = stripHeight
            contentInsets = safeAreaInsets
            contentLeadingConstraint?.constant = 12 + safeAreaInsets.left
            contentTrailingConstraint?.constant = -(12 + safeAreaInsets.right)
            contentBottomConstraint?.constant = -(14 + safeAreaInsets.bottom)
            contentWidthConstraint?.constant = -(24 + safeAreaInsets.left + safeAreaInsets.right)
            setNeedsLayout()
        }
        if appliedPalette != palette {
            appliedPalette = palette
            applyPalette(palette)
        }
        syncControlValues()
    }

    private func applyPalette(_ palette: KeyboardPalette) {
        let textColor = UIColor(palette.text)
        let secondaryColor = UIColor(palette.secondaryText)
        let accentColor = UIColor(palette.accent)
        let accentTextColor = UIColor(palette.accentText)
        let tileColor = UIColor(palette.tile)
        let chipColor = UIColor(palette.chip)

        backButton.apply(background: chipColor, text: textColor)
        statusCard.backgroundColor = tileColor
        fullAccessRow.apply(textColor: textColor)
        appGroupRow.apply(textColor: textColor)
        safeModeRow.apply(textColor: textColor)
        copyReportButton.apply(tint: accentColor)
        addWordButton.apply(tint: accentColor)
        clearDictionaryButton.apply(tint: .systemRed)
        resetDiagnosticsButton.apply(tint: accentColor)
        savedWordsBar.apply(chip: chipColor, text: textColor, secondary: secondaryColor)

        sectionHeaders.forEach { $0.textColor = secondaryColor }
        primaryLabels.forEach { $0.textColor = textColor }
        secondaryLabels.forEach { $0.textColor = secondaryColor }

        switchRows.forEach { $0.apply(textColor: textColor, accentColor: accentColor) }
        strengthSlider.minimumTrackTintColor = accentColor
        hapticStyleChips.apply(chip: chipColor, accent: accentColor, text: textColor, accentText: accentTextColor)
        soundStyleChips.apply(chip: chipColor, accent: accentColor, text: textColor, accentText: accentTextColor)
        longPressChips.apply(chip: chipColor, accent: accentColor, text: textColor, accentText: accentTextColor)
        timingRows.forEach { $0.apply(textColor: textColor, accentColor: accentColor) }
        counterRows.forEach { $0.apply(textColor: textColor) }
    }

    private func syncControlValues() {
        let preferences = engine.preferences

        fullAccessRow.configure(
            isOK: engine.hasFullAccess,
            text: engine.hasFullAccess
                ? "Acceso total activado"
                : "Sin acceso total: actívalo en Ajustes › General › Teclado › Teclados › Super Teclado"
        )
        appGroupRow.configure(
            isOK: SharedClipboardStore.isAppGroupAvailable,
            text: SharedClipboardStore.isAppGroupAvailable
                ? "Conectado con la app"
                : "La firma no incluye el App Group: la app no puede cambiar estos ajustes. Cámbialos aquí."
        )
        safeModeRow.isHidden = !engine.safeMode
        if engine.safeMode {
            safeModeRow.configure(isOK: false, text: "Modo seguro: sin sugerencias tras varios cierres")
        }

        hapticsSwitchRow.setOn(preferences.haptics)
        if hapticsDetailsStack.isHidden == preferences.haptics {
            hapticsDetailsStack.isHidden = !preferences.haptics
        }
        if let hapticIndex = HapticStyleOption.allCases.firstIndex(of: preferences.hapticsStyle) {
            hapticStyleChips.setSelectedIndex(hapticIndex)
        }
        if !strengthSlider.isTracking {
            let snapped = snappedStrength(preferences.hapticsStrength)
            if abs(Double(strengthSlider.value) - snapped) > 0.005 {
                strengthSlider.value = Float(snapped)
            }
            strengthValueLabel.text = "\(Int((snapped * 100).rounded())) %"
        }

        soundSwitchRow.setOn(preferences.sound)
        if soundStyleChips.isHidden == preferences.sound {
            soundStyleChips.isHidden = !preferences.sound
        }
        if let soundIndex = KeySoundStyle.allCases.firstIndex(of: preferences.soundStyle) {
            soundStyleChips.setSelectedIndex(soundIndex)
        }

        glideSwitchRow.setOn(preferences.glideTyping)
        autocorrectSwitchRow.setOn(preferences.autocorrect)
        spaceAfterSuggestionRow.setOn(preferences.spaceAfterSuggestion)
        smartTouchRow.setOn(preferences.smartTouch)
        longPressSymbolsSwitchRow.setOn(preferences.longPressSymbols)
        let longPressOption = SettingsLongPressOption(milliseconds: preferences.longPressDelay)
        if let delayIndex = SettingsLongPressOption.allCases.firstIndex(of: longPressOption) {
            longPressChips.setSelectedIndex(delayIndex)
        }
        numberRowSwitchRow.setOn(preferences.numberRow)
        keyBordersSwitchRow.setOn(preferences.keyBorders)
        incognitoSwitchRow.setOn(preferences.incognito)
        showSpeedRow.setOn(preferences.showSpeed)
    }

    /// Actualiza la lista de palabras recordadas al abrir ⚙️ o al modificar el diccionario.
    func refreshPersonalDictionary() {
        let words = engine.savedPersonalWords(limit: 40)
        if words.isEmpty {
            dictionarySummaryLabel.text = "El teclado aprende automáticamente las palabras que usas. También puedes pulsar «+ palabra» en la barra al escribir, o mantener una sugerencia para olvidarla."
            savedWordsBar.isHidden = true
            clearDictionaryButton.isHidden = true
        } else {
            let countLabel = words.count == 1 ? "1 palabra recordada" : "\(words.count) palabras recordadas"
            dictionarySummaryLabel.text = "\(countLabel) · Toca una palabra para olvidarla, o pulsa «+ palabra» en la barra al escribir."
            savedWordsBar.setWords(words)
            savedWordsBar.isHidden = false
            clearDictionaryButton.isHidden = false
        }
    }

    /// Actualiza los números del diagnóstico al abrir el panel o al pulsar «Poner a cero».
    func refreshDiagnostics() {
        let diagnostics = engine.touchDiagnostics
        speedSummaryLabel.isHidden = diagnostics.delivery.isEmpty
        if !diagnostics.delivery.isEmpty {
            speedSummaryLabel.text = "Velocidad · iOS \(TouchDiagnostics.summary(diagnostics.delivery)) · teclado \(TouchDiagnostics.summary(diagnostics.handling)) · bloqueos \(diagnostics.stalls)"
        }
        deliveryRow.setValue(TouchDiagnostics.summary(diagnostics.delivery))
        handlingRow.setValue(TouchDiagnostics.summary(diagnostics.handling))
        feedbackRow.setValue(TouchDiagnostics.summary(diagnostics.feedback))
        latenessRow.setValue(TouchDiagnostics.summary(diagnostics.lateness))
        stallsRow.setValue(
            diagnostics.stalls == 0
                ? "0"
                : String(format: "%d · el mayor %.0f ms", diagnostics.stalls, diagnostics.longestStall)
        )
        touchesRow.setValue(diagnostics.touches)
        typedRow.setValue(diagnostics.typed)
        rolloversRow.setValue(diagnostics.rollovers)
        cancelledTypedRow.setValue(diagnostics.cancelledTyped)
        cancelledLostRow.setValue(diagnostics.cancelledLost)
        unfinishedRow.setValue(diagnostics.unfinished)
        ignoredRow.setValue(diagnostics.ignored)
        glidesRow.setValue(diagnostics.glides)
        glidesAsTapsRow.setValue(diagnostics.glidesAsTaps)
        cursorSwipesRow.setValue(diagnostics.cursorSwipes)
        alternatesRow.setValue(diagnostics.alternates)
        smartChoicesRow.setValue(diagnostics.smartChoices)

        let hasRecent = !diagnostics.recent.isEmpty
        recentTitleLabel.isHidden = !hasRecent
        recentBodyLabel.isHidden = !hasRecent
        recentBodyLabel.text = hasRecent ? diagnostics.recent.joined(separator: "\n") : nil
    }
}

// MARK: Controles UIKit nativos del panel

@MainActor
final class SettingsBackButton: UIControl {
    var onDown: () -> Void = {}
    var onTap: () -> Void = {}

    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityLabel = "Volver"
        accessibilityTraits = .button

        iconView.image = UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        )
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false

        label.text = "ABC"
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.isUserInteractionEnabled = false

        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

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
        UIView.withoutAnimation {
            layer.cornerRadius = bounds.height / 2
        }
    }

    func apply(background: UIColor, text: UIColor) {
        backgroundColor = background
        iconView.tintColor = text
        label.textColor = text
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

@MainActor
private final class SettingsStatusRow: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private var lastIsOK: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(textColor: UIColor) {
        label.textColor = textColor
    }

    func configure(isOK: Bool, text: String) {
        if lastIsOK != isOK {
            lastIsOK = isOK
            let name = isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            iconView.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
            iconView.tintColor = isOK ? .systemGreen : .systemOrange
        }
        if label.text != text { label.text = text }
    }
}

@MainActor
final class SettingsSwitchRow: UIView {
    var onChange: (Bool) -> Void = { _ in }
    private let label = UILabel()
    let toggle = UISwitch()

    init(title: String) {
        super.init(frame: .zero)
        label.text = title
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.accessibilityLabel = title
        toggle.addTarget(self, action: #selector(valueChanged), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(textColor: UIColor, accentColor: UIColor) {
        label.textColor = textColor
        toggle.onTintColor = accentColor
    }

    func setOn(_ value: Bool) {
        if toggle.isOn != value { toggle.setOn(value, animated: false) }
    }

    @objc private func valueChanged() {
        onChange(toggle.isOn)
    }
}

@MainActor
final class SettingsActionButton: UIControl {
    var onDown: () -> Void = {}
    var onTap: () -> Void = {}

    private let iconView = UIImageView()
    private let label = UILabel()

    init(title: String, symbol: String?) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let symbol {
            iconView.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            )
            iconView.contentMode = .scaleAspectFit
            stack.addArrangedSubview(iconView)
        }
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: symbol == nil ? .medium : .semibold)
        stack.addArrangedSubview(label)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(released), for: .touchUpInside)
        addTarget(self, action: #selector(abandoned), for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(tint: UIColor) {
        iconView.tintColor = tint
        label.textColor = tint
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

@MainActor
private final class SettingsChipPill: UIControl {
    var onTap: () -> Void = {}
    private let label = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button

        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30)
        ])

        addTarget(self, action: #selector(pressed), for: .touchDown)
        addTarget(self, action: #selector(released), for: .touchUpInside)
        addTarget(self, action: #selector(abandoned), for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(selected: Bool, chip: UIColor, accent: UIColor, text: UIColor, accentText: UIColor) {
        backgroundColor = selected ? accent : chip
        label.textColor = selected ? accentText : text
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    @objc private func pressed() { alpha = 0.6 }
    @objc private func released() { alpha = 1; onTap() }
    @objc private func abandoned() { alpha = 1 }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }
}

@MainActor
final class SettingsChipBar: UIScrollView {
    var onSelect: (Int) -> Void = { _ in }
    private var pills: [SettingsChipPill] = []
    private var selectedIndex = 0
    private var chipColor: UIColor = .secondarySystemFill
    private var accentColor: UIColor = .systemBlue
    private var textColor: UIColor = .label
    private var accentTextColor: UIColor = .white

    init(titles: [String]) {
        super.init(frame: .zero)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = true
        canCancelContentTouches = true
        isDirectionalLockEnabled = false
        alwaysBounceVertical = false
        contentInsetAdjustmentBehavior = .never

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, title) in titles.enumerated() {
            let pill = SettingsChipPill(title: title)
            pill.onTap = { [weak self] in self?.onSelect(index) }
            pills.append(pill)
            stack.addArrangedSubview(pill)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Si todos los chips caben en pantalla, desactivar el scroll horizontal evita cualquier
        // competencia de gestos con el desplazamiento vertical del panel de ajustes.
        let overflows = contentSize.width > bounds.width + 1
        if isScrollEnabled != overflows { isScrollEnabled = overflows }
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard isScrollEnabled else { return false }
        let velocity = panGestureRecognizer.velocity(in: self)
        let translation = panGestureRecognizer.translation(in: self)
        let movement = velocity == .zero ? translation : velocity
        return abs(movement.x) > abs(movement.y) * 1.2
    }

    func apply(chip: UIColor, accent: UIColor, text: UIColor, accentText: UIColor) {
        chipColor = chip
        accentColor = accent
        textColor = text
        accentTextColor = accentText
        refreshStyles()
    }

    func setSelectedIndex(_ index: Int) {
        guard selectedIndex != index else { return }
        selectedIndex = index
        refreshStyles()
    }

    private func refreshStyles() {
        for (index, pill) in pills.enumerated() {
            pill.apply(
                selected: index == selectedIndex,
                chip: chipColor,
                accent: accentColor,
                text: textColor,
                accentText: accentTextColor
            )
        }
    }
}

@MainActor
private final class SettingsTimingRow: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.numberOfLines = 0
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(textColor: UIColor, accentColor: UIColor) {
        titleLabel.textColor = textColor
        valueLabel.textColor = accentColor
    }

    func setValue(_ text: String) {
        if valueLabel.text != text { valueLabel.text = text }
    }
}

@MainActor
private final class SettingsCounterRow: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.numberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func apply(textColor: UIColor) {
        titleLabel.textColor = textColor
        valueLabel.textColor = textColor
    }

    func setValue(_ value: Int) {
        let text = "\(value)"
        if valueLabel.text != text { valueLabel.text = text }
    }
}

/// Barra horizontal de palabras recordadas del diccionario personal (con toque para eliminar).
/// Comparte las mismas reglas táctiles que `SettingsChipBar` para nunca trabar el scroll vertical.
@MainActor
private final class SettingsWordChipsBar: UIScrollView {
    var onRemove: (String) -> Void = { _ in }
    private let stack = UIStackView()
    private var currentWords: [String] = []
    private var chipColor: UIColor = .secondarySystemFill
    private var textColor: UIColor = .label
    private var secondaryColor: UIColor = .secondaryLabel

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = true
        canCancelContentTouches = true
        isDirectionalLockEnabled = false
        alwaysBounceVertical = false
        contentInsetAdjustmentBehavior = .never

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let overflows = contentSize.width > bounds.width + 1
        if isScrollEnabled != overflows { isScrollEnabled = overflows }
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard isScrollEnabled else { return false }
        let velocity = panGestureRecognizer.velocity(in: self)
        let translation = panGestureRecognizer.translation(in: self)
        let movement = velocity == .zero ? translation : velocity
        return abs(movement.x) > abs(movement.y) * 1.2
    }

    func apply(chip: UIColor, text: UIColor, secondary: UIColor) {
        chipColor = chip
        textColor = text
        secondaryColor = secondary
        rebuildChips()
    }

    func setWords(_ words: [String]) {
        guard words != currentWords else { return }
        currentWords = words
        rebuildChips()
    }

    private func rebuildChips() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for word in currentWords {
            let pill = SettingsChipPill(title: "\(word) ×")
            pill.apply(selected: false, chip: chipColor, accent: chipColor, text: textColor, accentText: secondaryColor)
            pill.accessibilityLabel = "Eliminar \(word) del diccionario"
            pill.onTap = { [weak self] in self?.onRemove(word) }
            stack.addArrangedSubview(pill)
        }
        setNeedsLayout()
    }
}
