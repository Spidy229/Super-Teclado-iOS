import XCTest
@testable import SuperTeclado

final class LanguagesAndExtrasTests: XCTestCase {
    func testEveryLanguageHasALayoutAndDictionaryName() {
        for language in KeyboardLanguage.allCases {
            XCTAssertEqual(language.dictionaryResource, "words-\(language.rawValue)")
            XCTAssertFalse(language.defaultLayout.rows.isEmpty)
        }
        XCTAssertEqual(KeyboardLanguage.french.defaultLayout, .azerty)
        XCTAssertEqual(KeyboardLanguage.german.defaultLayout, .qwertz)
        XCTAssertEqual(KeyboardLanguage.portuguese.defaultLayout, .cedilla)
    }

    func testLayoutRowsFitTenKeyUnits() {
        for layout in LetterLayout.allCases {
            XCTAssertLessThanOrEqual(layout.rows[0].count, 10)
            XCTAssertLessThanOrEqual(layout.rows[1].count, 10)
            XCTAssertLessThanOrEqual(layout.rows[2].count, 7)
            XCTAssertEqual(layout.offset(ofRow: 0), (10 - Double(layout.rows[0].count)) / 2, accuracy: 0.001)
        }
        XCTAssertEqual(LetterLayout.qwerty.offset(ofRow: 1), 0.5, accuracy: 0.001)
        XCTAssertFalse(LetterLayout.azerty.alphabet.contains("'"))
    }

    func testLettersWithoutOwnKeyFallBackToBaseKey() {
        XCTAssertEqual(LetterLayout.fallbackKey(for: "ñ"), "n")
        XCTAssertEqual(LetterLayout.fallbackKey(for: "ç"), "c")
        XCTAssertNil(LetterLayout.fallbackKey(for: "a"))
    }

    func testGlideWorksWithAzerty() {
        let dictionary = WordDictionary.parse("bonjour 1000\nbonsoir 500\nmerci 900\n")
        var centers: [Character: CGPoint] = [:]
        for (letter, position) in LetterLayout.azerty.unitPositions {
            centers[letter] = CGPoint(x: position.x * 37.5, y: position.y * 54)
        }
        let decoder = GlideDecoder(keyCenters: centers, keyWidth: 37.5)
        let path = WordDictionary.keyLetters("merci").compactMap { centers[$0] }
        XCTAssertEqual(decoder.decode(path: path, dictionary: dictionary).first, "merci")
    }

    func testSecondLanguageMigrationAndLayoutOverride() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        defaults.set(true, forKey: KeyboardPreferenceKey.englishSecondLanguage)
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).secondaryLanguage, .english)

        defaults.set("fr", forKey: KeyboardPreferenceKey.secondaryLanguage)
        defaults.set("qwertz", forKey: KeyboardPreferenceKey.layout)
        let preferences = KeyboardPreferences.load(from: defaults)
        XCTAssertEqual(preferences.secondaryLanguage, .french)
        XCTAssertEqual(preferences.letterLayout, .qwertz)

        defaults.set("es", forKey: KeyboardPreferenceKey.secondaryLanguage)
        XCTAssertNil(KeyboardPreferences.load(from: defaults).secondaryLanguage)
    }

    func testSoundsAndFavorites() throws {
        XCTAssertEqual(KeySoundStyle.modern.soundID(isDelete: true, isModifier: false), 1155)
        XCTAssertTrue((1200...1209).contains(KeySoundStyle.phone.soundID(isDelete: false, isModifier: false)))

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        defaults.set("😂 @ #", forKey: KeyboardPreferenceKey.favorites)
        XCTAssertEqual(KeyboardPreferences.load(from: defaults).favoriteItems, ["😂", "@", "#"])
    }

    func testCustomGradientChangesDarkness() {
        var colors = CustomThemeColors()
        XCTAssertTrue(colors.isDark)
        colors.background = RGBColor(red: 1, green: 1, blue: 1)
        colors.backgroundEnd = RGBColor(red: 0.9, green: 0.9, blue: 0.9)
        XCTAssertFalse(colors.isDark)
    }
}
