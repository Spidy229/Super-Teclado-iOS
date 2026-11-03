import XCTest
@testable import SuperTeclado

final class PredictionAndBackupTests: XCTestCase {
    private let model = BigramModel.parse("""
    <s>\tno 30|el 20|la 10
    por\tqué 50|favor 30|la 20
    """)

    func testBasePredictionsWithoutLearning() {
        XCTAssertEqual(BigramModel.rank(base: model.followers(of: "Por"), learned: [:]), ["qué", "favor", "la"])
        XCTAssertEqual(BigramModel.rank(base: model.sentenceStarters, learned: [:]).first, "no")
        XCTAssertTrue(model.followers(of: "desconocida").isEmpty)
    }

    func testLearnedWordsWinOverTheBase() {
        let ranked = BigramModel.rank(base: model.followers(of: "por"), learned: ["supuesto": 3, "rara": 1])
        XCTAssertEqual(ranked.first, "supuesto")
        XCTAssertFalse(ranked.contains("rara"))
    }

    func testShortcutVariables() {
        let date = Date(timeIntervalSince1970: 1_793_700_000)
        let expanded = ShortcutVariables.expand("{fecha} {hora}", now: date)
        XCTAssertFalse(expanded.contains("\u{7B}"))
        XCTAssertEqual(ShortcutVariables.expand("sin variables"), "sin variables")
    }

    func testCompactDictionaryKeepsAccentLookups() {
        let dictionary = WordDictionary.parse("está 200\nesta 100\ntambién 50\nhola 10\n")
        XCTAssertEqual(dictionary.bestForm(matching: "tambien"), "también")
        XCTAssertEqual(dictionary.bestForm(matching: "hola"), "hola")
        XCTAssertNil(dictionary.bestForm(matching: "xyz"))
        XCTAssertEqual(dictionary.count(of: "esta"), 100)
    }

    func testDiagnosticsCountUnexpectedExits() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "super-teclado-tests-\(UUID().uuidString)"))
        KeyboardDiagnostics.recordSessionStart(defaults: defaults)
        KeyboardDiagnostics.recordSessionEnd(defaults: defaults)
        KeyboardDiagnostics.recordSessionStart(defaults: defaults)
        KeyboardDiagnostics.recordSessionStart(defaults: defaults)
        KeyboardDiagnostics.recordMemory(availableMB: 30, defaults: defaults)
        KeyboardDiagnostics.recordMemory(availableMB: 12, defaults: defaults)

        let diagnostics = KeyboardDiagnostics.load(from: defaults)
        XCTAssertEqual(diagnostics.unexpectedExits, 1)
        XCTAssertEqual(diagnostics.lowestAvailableMemoryMB ?? 0, 12, accuracy: 0.01)
        XCTAssertTrue(diagnostics.report(appVersion: "2.6", lastActive: nil).contains("Cierres inesperados: 1"))
    }

    func testBackupValuesKeepTheirType() throws {
        XCTAssertEqual(BackupValue(true), .bool(true))
        XCTAssertEqual(BackupValue(42), .int(42))
        XCTAssertEqual(BackupValue(0.35), .double(0.35))
        XCTAssertEqual(BackupValue("es"), .string("es"))
        XCTAssertNil(BackupValue(Data()))
    }

    @MainActor
    func testBackupRoundTrip() throws {
        let backup = SuperTecladoBackup(
            createdAt: Date(timeIntervalSince1970: 1_793_700_000),
            appVersion: "2.6",
            items: [],
            folders: ["Trabajo"],
            learnedWords: ["finde": 3],
            learnedBigrams: ["buen": ["finde": 2]],
            shortcuts: ["qtal": "¿Qué tal?"],
            sharedSettings: ["keyboardTheme": .string("dark")],
            appSettings: ["maximumItems": .int(250)]
        )
        let decoded = try BackupService.decode(BackupService.encodeDetached(backup))
        XCTAssertEqual(decoded.folders, ["Trabajo"])
        XCTAssertEqual(decoded.shortcuts["qtal"], "¿Qué tal?")
        XCTAssertEqual(decoded.sharedSettings["keyboardTheme"], .string("dark"))
    }
}
