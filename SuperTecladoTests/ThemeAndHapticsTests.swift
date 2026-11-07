import XCTest
@testable import SuperTeclado

final class ThemeAndHapticsTests: XCTestCase {
    func testRGBColorHexRoundTrip() throws {
        let color = try XCTUnwrap(RGBColor(hex: "#FF8000"))
        XCTAssertEqual(color.hex, "FF8000")
        XCTAssertEqual(color.red, 1, accuracy: 0.001)
        XCTAssertNil(RGBColor(hex: "FF80"))
        XCTAssertGreaterThan(RGBColor(red: 1, green: 1, blue: 1).luminance, 0.9)
    }

    func testCustomThemeColorsAreSavedAndLoaded() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        var colors = CustomThemeColors()
        colors.background = RGBColor(red: 0.9, green: 0.9, blue: 0.9)
        colors.accent = try XCTUnwrap(RGBColor(hex: "1A73E8"))
        colors.save(to: defaults)

        let loaded = CustomThemeColors.load(from: defaults)
        XCTAssertEqual(loaded.accent.hex, "1A73E8")
        XCTAssertFalse(loaded.isDark)
        XCTAssertTrue(CustomThemeColors().isDark)
    }

    func testHapticAndLabelPreferences() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        var preferences = KeyboardPreferences.load(from: defaults)
        XCTAssertEqual(preferences.hapticsStrength, 0.6, accuracy: 0.001)
        XCTAssertEqual(preferences.hapticsStyle, .light)
        XCTAssertEqual(preferences.keyLabelSize, .normal)

        defaults.set(5.0, forKey: KeyboardPreferenceKey.hapticsStrength)
        defaults.set("heavy", forKey: KeyboardPreferenceKey.hapticsStyle)
        defaults.set("large", forKey: KeyboardPreferenceKey.keyLabelSize)
        preferences = KeyboardPreferences.load(from: defaults)
        XCTAssertEqual(preferences.hapticsStrength, 1, accuracy: 0.001)
        XCTAssertEqual(preferences.hapticsStyle, .heavy)
        XCTAssertGreaterThan(preferences.keyLabelSize.scale, 1)
    }

    func testPreferencesChangedInTheKeyboardAreSaved() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        var preferences = KeyboardPreferences()
        preferences.hapticsStrength = 0.9
        preferences.hapticsStyle = .rigid
        preferences.sound = true
        preferences.numberRow = true
        preferences.secondaryLanguage = .english
        preferences.save(to: defaults)

        XCTAssertEqual(KeyboardPreferences.load(from: defaults), preferences)
    }

    func testGlassTransparencyIsClampedSavedAndVeilsTheBackground() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).glassTransparency, 1, accuracy: 0.001)

        defaults.set(-2.0, forKey: KeyboardPreferenceKey.glassTransparency)
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).glassTransparency, 0, accuracy: 0.001)

        var preferences = KeyboardPreferences()
        preferences.glassTransparency = 0.4
        preferences.save(to: defaults)
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).glassTransparency, 0.4, accuracy: 0.001)

        // 100 %: sin velo, se ve el fondo translúcido de iOS. Menos: un velo cada vez más opaco.
        let clear = KeyboardPalette.make(theme: .glass, systemIsDark: true, glassTransparency: 1)
        let veiled = KeyboardPalette.make(theme: .glass, systemIsDark: true, glassTransparency: 0.4)
        XCTAssertEqual(clear.background, .clear)
        XCTAssertNotEqual(veiled.background, clear.background)
        XCTAssertEqual(
            KeyboardPalette.make(theme: .dark, systemIsDark: true, glassTransparency: 0.2),
            KeyboardPalette.make(theme: .dark, systemIsDark: true)
        )
    }

    func testSettingsTransferCopiesSettingsButNotWhatTheKeyboardLearned() throws {
        let app = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        let keyboard = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        app.set(false, forKey: KeyboardPreferenceKey.autocorrect)
        app.set(KeyboardThemeOption.glass.rawValue, forKey: KeyboardPreferenceKey.theme)
        app.set(["hola": 9], forKey: KeyboardPreferenceKey.learnedWords)
        keyboard.set(["mio": 4], forKey: KeyboardPreferenceKey.learnedWords)

        let data = try XCTUnwrap(KeyboardSettingsTransfer.payload(from: app))
        XCTAssertGreaterThan(KeyboardSettingsTransfer.apply(data, to: keyboard), 0)

        let preferences = KeyboardPreferences.load(from: keyboard)
        XCTAssertFalse(preferences.autocorrect)
        XCTAssertEqual(preferences.theme, .glass)
        XCTAssertEqual(keyboard.dictionary(forKey: KeyboardPreferenceKey.learnedWords) as? [String: Int], ["mio": 4])
        XCTAssertEqual(KeyboardSettingsTransfer.apply(Data("no".utf8), to: keyboard), 0)
    }

    func testSmartTouchAndLongPressDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        var preferences = KeyboardPreferences.load(from: defaults)
        XCTAssertTrue(preferences.smartTouch)
        XCTAssertTrue(preferences.spaceAfterSuggestion)
        XCTAssertTrue(preferences.showSpeed)
        XCTAssertEqual(preferences.longPressDelay, 400)

        // El antiguo «Normal» (330 ms) pasa al nuevo; un valor elegido se respeta.
        defaults.set(330, forKey: KeyboardPreferenceKey.longPressDelay)
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).longPressDelay, 400)
        defaults.set(550, forKey: KeyboardPreferenceKey.longPressDelay)
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).longPressDelay, 550)

        preferences.smartTouch = false
        preferences.showSpeed = false
        preferences.save(to: defaults)
        XCTAssertFalse(KeyboardPreferences.load(from: defaults).smartTouch)
        XCTAssertFalse(KeyboardPreferences.load(from: defaults).showSpeed)
    }

    func testCustomThemeIsIncludedInThemeList() {
        XCTAssertTrue(KeyboardThemeOption.allCases.contains(.custom))
        XCTAssertNil(KeyboardThemeOption.custom.isDark)
    }
}
