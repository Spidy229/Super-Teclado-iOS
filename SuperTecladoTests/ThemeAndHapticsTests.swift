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

    func testCustomThemeIsIncludedInThemeList() {
        XCTAssertTrue(KeyboardThemeOption.allCases.contains(.custom))
        XCTAssertNil(KeyboardThemeOption.custom.isDark)
    }
}
