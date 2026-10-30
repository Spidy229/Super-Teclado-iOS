import XCTest
@testable import SuperTeclado

final class KeyboardTextLogicTests: XCTestCase {
    func testCurrentWordStopsAtSeparators() {
        XCTAssertEqual(KeyboardTextLogic.currentWord(before: "hola mund"), "mund")
        XCTAssertEqual(KeyboardTextLogic.currentWord(before: "¿qué"), "qué")
        XCTAssertEqual(KeyboardTextLogic.currentWord(before: "hola "), "")
        XCTAssertEqual(KeyboardTextLogic.currentWord(before: nil), "")
    }

    func testSentenceCapitalization() {
        XCTAssertTrue(KeyboardTextLogic.shouldCapitalize(context: nil, mode: .sentences))
        XCTAssertTrue(KeyboardTextLogic.shouldCapitalize(context: "Hola. ", mode: .sentences))
        XCTAssertTrue(KeyboardTextLogic.shouldCapitalize(context: "Fin. ¿", mode: .sentences))
        XCTAssertTrue(KeyboardTextLogic.shouldCapitalize(context: "línea\n", mode: .sentences))
        XCTAssertFalse(KeyboardTextLogic.shouldCapitalize(context: "hola ", mode: .sentences))
        XCTAssertFalse(KeyboardTextLogic.shouldCapitalize(context: "Hola.", mode: .sentences))
        XCTAssertFalse(KeyboardTextLogic.shouldCapitalize(context: "", mode: .none))
        XCTAssertTrue(KeyboardTextLogic.shouldCapitalize(context: "Ana ", mode: .words))
    }

    func testDoubleSpacePeriod() {
        XCTAssertTrue(KeyboardTextLogic.shouldConvertDoubleSpace(context: "hola "))
        XCTAssertFalse(KeyboardTextLogic.shouldConvertDoubleSpace(context: "hola. "))
        XCTAssertFalse(KeyboardTextLogic.shouldConvertDoubleSpace(context: "hola  "))
    }

    func testWordDeletionAndCursorOffsets() {
        XCTAssertEqual(KeyboardTextLogic.wordDeletionLength(context: "hola mundo  "), 7)
        XCTAssertEqual(KeyboardTextLogic.wordDeletionLength(context: "hola,"), 1)
        XCTAssertEqual(KeyboardTextLogic.nextWordOffset(after: " mundo feliz"), 6)
        XCTAssertEqual(KeyboardTextLogic.offsetToLineStart(before: "a\nbcd"), 3)
        XCTAssertEqual(KeyboardTextLogic.offsetToLineEnd(after: "xy\nz"), 2)
    }

    func testSuggestionCaseMatchesTypedWord() {
        XCTAssertEqual(KeyboardTextLogic.matchCase("hola", to: "Ho"), "Hola")
        XCTAssertEqual(KeyboardTextLogic.matchCase("hola", to: "HO"), "HOLA")
        XCTAssertEqual(KeyboardTextLogic.matchCase("hola", to: "ho"), "hola")
    }

    func testOneTimeCodeDetection() {
        XCTAssertTrue(KeyboardTextLogic.isLikelyOneTimeCode(" 123456 "))
        XCTAssertFalse(KeyboardTextLogic.isLikelyOneTimeCode("12"))
        XCTAssertFalse(KeyboardTextLogic.isLikelyOneTimeCode("Hola 1234"))
    }

    func testPreferencesUseGboardDefaults() {
        let defaults = UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)")
        let preferences = KeyboardPreferences.load(from: defaults)
        XCTAssertEqual(preferences, KeyboardPreferences())
        XCTAssertTrue(preferences.autocorrect)
        XCTAssertFalse(preferences.numberRow)
    }
}
