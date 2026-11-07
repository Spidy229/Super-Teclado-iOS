import XCTest
@testable import SuperTeclado

final class DictionaryAndGlideTests: XCTestCase {
    private let dictionary = WordDictionary.parse("""
    de 14459520
    que 14421005
    qué 4166708
    hola 1000000
    también 488057
    mañana 283391
    casa 300000
    cosa 280000
    gracias 900000
    dinero 200000
    di 150000
    perro 60000
    pero 2000000
    """)

    func testDictionaryLookupsIgnoreAccentsWhenAsked() {
        XCTAssertTrue(dictionary.contains("Hola"))
        XCTAssertFalse(dictionary.contains("tambien"))
        XCTAssertEqual(dictionary.bestForm(matching: "tambien"), "también")
        XCTAssertEqual(dictionary.bestForm(matching: "manana"), "mañana")
        XCTAssertEqual(dictionary.completions(for: "gra", limit: 3), ["gracias"])
        XCTAssertEqual(dictionary.completions(for: "tamb", limit: 3), ["también"])
    }

    func testPrefixWeightTellsWhichKeyContinuesAWord() {
        // «ho» + «l» sigue «hola»; «ho» + «k» no sigue ninguna palabra.
        XCTAssertEqual(dictionary.prefixWeight("hol"), 1_000_000)
        XCTAssertEqual(dictionary.prefixWeight("hok"), 0)
        // Las tildes no cuentan como teclas, pero la «ñ» sí.
        XCTAssertEqual(dictionary.prefixWeight("tamb"), 488_057)
        XCTAssertEqual(dictionary.prefixWeight("mañ"), 283_391)
        XCTAssertEqual(dictionary.prefixWeight("man"), 0)
        XCTAssertEqual(dictionary.prefixWeight("qu"), 14_421_005 + 4_166_708)
        XCTAssertEqual(dictionary.prefixWeight("per"), 2_060_000)
        XCTAssertGreaterThan(dictionary.prefixWeight(""), dictionary.prefixWeight("d"))
    }

    func testTypoCorrectorPrefersNeighbouringKeys() {
        XCTAssertEqual(TypoCorrector.candidates(for: "qeu", in: dictionary).first?.word, "que")
        XCTAssertEqual(TypoCorrector.candidates(for: "graciss", in: dictionary).first?.word, "gracias")
        XCTAssertEqual(TypoCorrector.candidates(for: "dinerp", in: dictionary).first?.word, "dinero")
    }

    func testGlideDecoderRecognisesIdealPaths() {
        let unit: CGFloat = 37.5
        var centers: [Character: CGPoint] = [:]
        for (letter, position) in LetterLayout.spanish.unitPositions {
            centers[letter] = CGPoint(x: CGFloat(position.x) * unit, y: CGFloat(position.y) * 54)
        }
        let decoder = GlideDecoder(keyCenters: centers, keyWidth: unit)

        for word in ["hola", "gracias", "dinero", "casa"] {
            let path = WordDictionary.keyLetters(word).compactMap { centers[$0] }
            XCTAssertEqual(decoder.decode(path: path, dictionary: dictionary).first, word, word)
        }
    }

    func testGlideDecoderIgnoresTaps() {
        let decoder = GlideDecoder(keyCenters: ["a": .zero, "s": CGPoint(x: 37, y: 0)], keyWidth: 37)
        XCTAssertTrue(decoder.decode(path: [.zero, CGPoint(x: 2, y: 1)], dictionary: dictionary).isEmpty)
    }

    func testPreviousWordStopsAtPunctuation() {
        XCTAssertEqual(KeyboardTextLogic.previousWord(before: "hola mund"), "hola")
        XCTAssertEqual(KeyboardTextLogic.previousWord(before: "hola "), "hola")
        XCTAssertNil(KeyboardTextLogic.previousWord(before: "hola. "))
        XCTAssertNil(KeyboardTextLogic.previousWord(before: "mund"))
    }

    func testPersonalShortcutsAndWords() {
        defer {
            PersonalDictionary.removeShortcut("qtal")
            PersonalDictionary.removeWord("finde")
        }

        XCTAssertTrue(PersonalDictionary.setShortcut(" QTal ", phrase: "¿Qué tal?"))
        XCTAssertEqual(PersonalDictionary.shortcuts()["qtal"], "¿Qué tal?")
        XCTAssertFalse(PersonalDictionary.setShortcut("dos palabras", phrase: "x"))

        PersonalDictionary.addWord("Finde")
        XCTAssertGreaterThanOrEqual(PersonalDictionary.learnedWords()["finde"] ?? 0, PersonalDictionary.knownThreshold)
        PersonalDictionary.removeWord("finde")
        XCTAssertNil(PersonalDictionary.learnedWords()["finde"])
    }
}
