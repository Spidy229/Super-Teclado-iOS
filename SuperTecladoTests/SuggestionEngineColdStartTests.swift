import UIKit
import XCTest
@testable import SuperTeclado

// El motor de producción se compila en este destino y accede mediante @testable a las
// implementaciones Shared de la app, sin copiarlas ni sustituir el cálculo de sugerencias.

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
    func testRejectingAColdAccentKeepsTheOriginalWithoutSystemValidation() async {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.engine.autocorrection(for: "tambien"), "también")

        fixture.engine.reject("tambien")

        XCTAssertNil(fixture.engine.autocorrection(for: "tambien"))
        let result = await fixture.engine.result(for: "tambien")
        XCTAssertNil(result.autocorrection)
        XCTAssertFalse(result.needsSpellCheck)
        XCTAssertEqual(result.slots[1], SuggestionItem(text: "tambien", kind: .typed))
        XCTAssertEqual(fixture.validator.creations, 0)
        XCTAssertTrue(fixture.validator.words.isEmpty)
    }

    @MainActor
    func testRejectedShortcutStopsExpandingWhileOtherShortcutsStillWork() async {
        let fixture = makeFixture()
        fixture.engine.setLexicon([
            (input: "qtal", replacement: "¿Qué tal?"),
            (input: "bds", replacement: "Buenos días")
        ])
        XCTAssertEqual(fixture.engine.autocorrection(for: "qtal"), "¿Qué tal?")

        fixture.engine.reject("Qtal", persist: false)

        XCTAssertNil(fixture.engine.autocorrection(for: "qtal"))
        let result = await fixture.engine.result(for: "qtal")
        XCTAssertNil(result.autocorrection)
        XCTAssertEqual(result.slots[1], SuggestionItem(text: "qtal", kind: .typed))
        XCTAssertEqual(fixture.engine.autocorrection(for: "bds"), "Buenos días")
        XCTAssertEqual(fixture.validator.creations, 0)
        XCTAssertTrue(fixture.validator.words.isEmpty)
    }

    @MainActor
    func testPersistentRejectionKeepsLocalLearningWithoutLearningPrivateWords() async {
        let fixture = makeFixture()
        fixture.engine.reject("spidy")
        fixture.engine.reject("privado", persist: false)

        let learned = await fixture.engine.result(for: "spi")
        XCTAssertTrue(learned.slots.compactMap { $0 }.contains {
            $0.text == "spidy" && $0.kind == .completion
        })
        let privateWord = await fixture.engine.result(for: "pri")
        XCTAssertFalse(privateWord.slots.compactMap { $0 }.contains { $0.text == "privado" })
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
