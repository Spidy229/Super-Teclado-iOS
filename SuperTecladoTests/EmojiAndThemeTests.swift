import XCTest
@testable import SuperTeclado

final class EmojiAndThemeTests: XCTestCase {
    private let index = EmojiSearchIndex.parse("""
    😂\tcara llorando de risa\tcara|felicidad|lágrima|risa
    🍕\tpizza\tporción|restaurante
    ❤\tcorazón rojo\tcorazón|emoción|rojo
    🇪🇸\tBandera: España\tBandera
    """)

    func testEmojiSearchMatchesNamesAndKeywordsWithoutAccents() {
        let emojis = ["😂", "🍕", "❤️", "🇪🇸"]
        XCTAssertEqual(index.search("risa", in: emojis), ["😂"])
        XCTAssertEqual(index.search("corazon", in: emojis), ["❤️"])
        XCTAssertEqual(index.search("espa", in: emojis), ["🇪🇸"])
        XCTAssertEqual(index.search("cara llor", in: emojis), ["😂"])
        XCTAssertTrue(index.search("xyz", in: emojis).isEmpty)
        XCTAssertEqual(index.name(for: "❤️"), "corazon rojo")
    }

    func testThemeCycleSkipsPhotoWithoutImage() {
        XCTAssertEqual(KeyboardThemeOption.system.next(includingPhoto: false), .light)
        XCTAssertEqual(KeyboardThemeOption.lavender.next(includingPhoto: false), .system)
        XCTAssertEqual(KeyboardThemeOption.lavender.next(includingPhoto: true), .photo)
        XCTAssertNil(KeyboardThemeOption.system.isDark)
        XCTAssertEqual(KeyboardThemeOption.rose.isDark, false)
        XCTAssertEqual(KeyboardThemeOption.photo.isDark, true)
    }

    func testSecondLanguageIsMergedWithLowerWeight() throws {
        let directory = FileManager.default.temporaryDirectory
        let spanish = directory.appendingPathComponent("es-\(UUID().uuidString).txt")
        let english = directory.appendingPathComponent("en-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: spanish)
            try? FileManager.default.removeItem(at: english)
        }
        try "hola 1000\nno 900\n".write(to: spanish, atomically: true, encoding: .utf8)
        try "hello 1000\nno 5000\n".write(to: english, atomically: true, encoding: .utf8)

        let dictionary = try XCTUnwrap(WordDictionary.load(from: spanish, secondary: english, secondaryWeight: 0.5))
        XCTAssertTrue(dictionary.contains("hola"))
        XCTAssertTrue(dictionary.contains("hello"))
        XCTAssertEqual(dictionary.count(of: "hello"), 500)
        XCTAssertEqual(dictionary.count(of: "no"), 2500)

        let spanishOnly = try XCTUnwrap(WordDictionary.load(from: spanish, secondary: nil, secondaryWeight: 0.5))
        XCTAssertFalse(spanishOnly.contains("hello"))
    }

    func testNewPreferencesDefaults() {
        let defaults = UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)")
        let preferences = KeyboardPreferences.load(from: defaults)
        XCTAssertFalse(preferences.incognito)
        XCTAssertFalse(preferences.englishSecondLanguage)
        XCTAssertEqual(preferences.theme, .system)
        XCTAssertEqual(preferences.backgroundDim, 0.35, accuracy: 0.001)
    }
}
