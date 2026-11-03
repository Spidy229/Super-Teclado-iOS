import Foundation

/// Datos que el teclado deja en el App Group para que la app muestre cómo funciona en el
/// dispositivo: memoria disponible, tiempo de carga del diccionario y cierres inesperados.
struct KeyboardDiagnostics: Equatable {
    var availableMemoryMB: Double?
    var lowestAvailableMemoryMB: Double?
    var dictionaryLoadMilliseconds: Int?
    var dictionaryWordCount: Int?
    var languages: String?
    var unexpectedExits = 0
    var lastUnexpectedExit: Date?
    var sessionOpen = false

    private enum Key {
        static let availableMemory = "diagnosticsAvailableMemoryMB"
        static let lowestMemory = "diagnosticsLowestAvailableMemoryMB"
        static let loadTime = "diagnosticsDictionaryLoadMs"
        static let wordCount = "diagnosticsDictionaryWordCount"
        static let languages = "diagnosticsLanguages"
        static let unexpectedExits = "diagnosticsUnexpectedExits"
        static let lastUnexpectedExit = "diagnosticsLastUnexpectedExit"
        static let sessionOpen = "diagnosticsSessionOpen"
    }

    static func load(from defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) -> KeyboardDiagnostics {
        var diagnostics = KeyboardDiagnostics()
        guard let defaults else { return diagnostics }
        func double(_ key: String) -> Double? { defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key) }
        func int(_ key: String) -> Int? { defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key) }
        diagnostics.availableMemoryMB = double(Key.availableMemory)
        diagnostics.lowestAvailableMemoryMB = double(Key.lowestMemory)
        diagnostics.dictionaryLoadMilliseconds = int(Key.loadTime)
        diagnostics.dictionaryWordCount = int(Key.wordCount)
        diagnostics.languages = defaults.string(forKey: Key.languages)
        diagnostics.unexpectedExits = defaults.integer(forKey: Key.unexpectedExits)
        diagnostics.lastUnexpectedExit = double(Key.lastUnexpectedExit).map(Date.init(timeIntervalSince1970:))
        diagnostics.sessionOpen = defaults.bool(forKey: Key.sessionOpen)
        return diagnostics
    }

    /// El teclado se abre. Si la sesión anterior no se cerró, iOS lo terminó mientras estaba
    /// visible (lo normal es que sea por falta de memoria).
    static func recordSessionStart(defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        guard let defaults else { return }
        if defaults.bool(forKey: Key.sessionOpen) {
            defaults.set(defaults.integer(forKey: Key.unexpectedExits) + 1, forKey: Key.unexpectedExits)
            defaults.set(Date().timeIntervalSince1970, forKey: Key.lastUnexpectedExit)
        }
        defaults.set(true, forKey: Key.sessionOpen)
    }

    static func recordSessionEnd(defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        defaults?.set(false, forKey: Key.sessionOpen)
    }

    static func recordMemory(availableMB: Double, defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        guard let defaults else { return }
        defaults.set(availableMB, forKey: Key.availableMemory)
        let lowest = defaults.object(forKey: Key.lowestMemory) == nil ? availableMB : defaults.double(forKey: Key.lowestMemory)
        defaults.set(min(lowest, availableMB), forKey: Key.lowestMemory)
    }

    static func recordDictionary(
        milliseconds: Int,
        wordCount: Int,
        languages: String,
        defaults: UserDefaults? = SharedClipboardStore.sharedDefaults
    ) {
        defaults?.set(milliseconds, forKey: Key.loadTime)
        defaults?.set(wordCount, forKey: Key.wordCount)
        defaults?.set(languages, forKey: Key.languages)
    }

    static func reset(defaults: UserDefaults? = SharedClipboardStore.sharedDefaults) {
        for key in [Key.lowestMemory, Key.unexpectedExits, Key.lastUnexpectedExit] {
            defaults?.removeObject(forKey: key)
        }
    }

    /// Texto para copiar y enviar cuando algo falla.
    func report(appVersion: String, lastActive: Date?) -> String {
        var lines = ["Super Teclado \(appVersion) · diagnóstico"]
        lines.append("Último uso del teclado: \(lastActive.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "nunca")")
        lines.append("Memoria disponible: \(availableMemoryMB.map { String(format: "%.0f MB", $0) } ?? "sin datos")")
        lines.append("Memoria disponible mínima: \(lowestAvailableMemoryMB.map { String(format: "%.0f MB", $0) } ?? "sin datos")")
        lines.append("Diccionario: \(dictionaryWordCount.map(String.init) ?? "?") palabras (\(languages ?? "?")) en \(dictionaryLoadMilliseconds.map { "\($0) ms" } ?? "?")")
        lines.append("Cierres inesperados: \(unexpectedExits)\(lastUnexpectedExit.map { ", el último \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")")
        return lines.joined(separator: "\n")
    }
}
