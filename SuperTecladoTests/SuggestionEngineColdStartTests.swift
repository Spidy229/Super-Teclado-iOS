import UIKit
import XCTest
@testable import SuperTeclado

// El motor y el catálogo se compilan también en este destino. Estos alias usan las mismas
// implementaciones Shared de la app, sin copiarlas ni sustituir el cálculo de sugerencias.
typealias WordDictionary = SuperTeclado.WordDictionary
typealias LetterLayout = SuperTeclado.LetterLayout
typealias PersonalDictionary = SuperTeclado.PersonalDictionary
typealias KeyboardTextLogic = SuperTeclado.KeyboardTextLogic
typealias TypoCorrector = SuperTeclado.TypoCorrector
typealias ShortcutVariables = SuperTeclado.ShortcutVariables
typealias BigramModel = SuperTeclado.BigramModel

final class SuggestionEngineColdStartTests: XCTestCase {
    @MainActor
    func testFirstTypoRemainsAManualSuggestionWithoutCreatingTheSystemChecker() async throws {
        let fixture = makeFixture()
        let result = await fixture.engine.result(for: "qeu")
        XCTAssertTrue(result.needsSpellCheck)
        XCTAssertEqual(result.autocorrection, "que")

        let slots = fixture.engine.slots(for: result, word: "qeu", includeEmoji: false)
        XCTAssertEqual(slots.compactMap { $0 }.first { $0.text == "que" }?.kind, .completion)
        XCTAssertFalse(slots.compactMap { $0 }.contains { $0.kind == .correction })
        XCTAssertNil(fixture.engine.autocorrection(for: "qeu"))
        XCTAssertNil(fixture.engine.autocorrection(for: "graciss"))
        XCTAssertEqual(fixture.validator.creations, 0)
        XCTAssertTrue(fixture.validator.words.isEmpty)
    }

    @MainActor
    func testIdleWarmUpRefreshesEligibilityAndAllowsAConfirmedTypoCorrection() async throws {
        let fixture = makeFixture()
        let result = await fixture.engine.result(for: "qeu")
        XCTAssertNil(fixture.engine.autocorrection(for: "qeu"))

        XCTAssertTrue(fixture.engine.warmUpChecker())
        XCTAssertFalse(fixture.engine.warmUpChecker())
        XCTAssertEqual(fixture.validator.creations, 1)
        XCTAssertEqual(fixture.validator.words, ["hola"])
        let slots = fixture.engine.slots(for: result, word: "qeu", includeEmoji: false)
        XCTAssertEqual(slots.compactMap { $0 }.first { $0.text == "que" }?.kind, .correction)

        XCTAssertEqual(fixture.engine.autocorrection(for: "qeu"), "que")
        XCTAssertEqual(fixture.validator.words, ["hola", "qeu"])
        XCTAssertEqual(fixture.validator.creations, 1)
    }

    @MainActor
    func testWarmCheckerKeepsAWordAcceptedByIOSUnchanged() async throws {
        let fixture = makeFixture(validWords: ["hola", "qeu"])
        XCTAssertTrue(fixture.engine.warmUpChecker())
        XCTAssertNil(fixture.engine.autocorrection(for: "qeu"))
        XCTAssertEqual(fixture.validator.words, ["hola", "qeu"])

        let result = await fixture.engine.result(for: "qeu")
        XCTAssertFalse(result.needsSpellCheck)
        XCTAssertNil(result.autocorrection)
        XCTAssertFalse(fixture.engine.slots(for: result, word: "qeu", includeEmoji: false)
            .compactMap { $0 }.contains { $0.kind == .correction })
    }

    @MainActor
    func testColdAccentsAndShortcutsDoNotNeedTheSystemChecker() async throws {
        let fixture = makeFixture()
        fixture.engine.setLexicon([(input: "qtal", replacement: "¿Qué tal?")])

        XCTAssertEqual(fixture.engine.autocorrection(for: "tambien"), "también")
        XCTAssertEqual(fixture.engine.autocorrection(for: "qtal"), "¿Qué tal?")
        let accent = await fixture.engine.result(for: "tambien")
        XCTAssertFalse(accent.needsSpellCheck)
        XCTAssertEqual(fixture.engine.slots(for: accent, word: "tambien", includeEmoji: false)
            .compactMap { $0 }.first { $0.text == "también" }?.kind, .correction)
        XCTAssertEqual(fixture.validator.creations, 0)
        XCTAssertTrue(fixture.validator.words.isEmpty)
    }

    @MainActor
    func testChangingLanguageRequiresAnotherIdleWarmUpBeforeTypoAutocorrection() async throws {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.engine.warmUpChecker())
        fixture.engine.setLanguage("en_US")
        let callsBeforeTyping = fixture.validator.words

        XCTAssertNil(fixture.engine.autocorrection(for: "qeu"))
        let result = await fixture.engine.result(for: "qeu")
        XCTAssertEqual(fixture.engine.slots(for: result, word: "qeu", includeEmoji: false)
            .compactMap { $0 }.first { $0.text == "que" }?.kind, .completion)
        XCTAssertEqual(fixture.validator.words, callsBeforeTyping)

        XCTAssertTrue(fixture.engine.warmUpChecker())
        XCTAssertEqual(fixture.validator.words, callsBeforeTyping + ["hola"])
        XCTAssertEqual(fixture.engine.autocorrection(for: "qeu"), "que")
        XCTAssertEqual(fixture.validator.creations, 1)
    }

    @MainActor
    func testNoDictionaryDoesNotCreateOrWarmTheSystemChecker() async {
        let validator = RecordingSpellValidator(validWords: [])
        let engine = SuggestionEngine(makeSpellValidator: {
            validator.creations += 1
            return validator
        })
        XCTAssertFalse(engine.warmUpChecker())
        XCTAssertNil(engine.autocorrection(for: "qeu"))
        XCTAssertEqual(validator.creations, 0)
        XCTAssertTrue(validator.words.isEmpty)
    }

    @MainActor
    private func makeFixture(validWords: Set<String> = ["hola"]) -> (engine: SuggestionEngine, validator: RecordingSpellValidator) {
        let validator = RecordingSpellValidator(validWords: validWords)
        let engine = SuggestionEngine(makeSpellValidator: {
            validator.creations += 1
            return validator
        })
        engine.setDictionary(WordDictionary.parse("""
        que 14421005
        gracias 900000
        también 488057
        hola 1000000
        """))
        return (engine, validator)
    }
}

@MainActor
private final class RecordingSpellValidator: SuggestionSpellValidating {
    let validWords: Set<String>
    var creations = 0
    private(set) var words: [String] = []

    init(validWords: Set<String>) { self.validWords = validWords }

    func isValidSpelling(_ word: String, language: String) -> Bool {
        words.append(word)
        return validWords.contains(word)
    }
}
