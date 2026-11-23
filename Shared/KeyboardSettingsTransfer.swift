import Foundation

/// Cuando la firma no incluye el App Group, la app y el teclado no comparten ajustes. La app
/// puede enviarlos por el portapapeles con un tipo propio: el teclado lo reconoce al abrirse,
/// copia los ajustes a los suyos y lo borra (no se guarda como algo copiado).
enum KeyboardSettingsTransfer {
    static let pasteboardType = "com.spidy229.superteclado.settings"

    /// Lo que aprende el teclado al escribir no viaja: lo de la app estaría desfasado.
    private static let excludedKeys: Set<String> = [
        KeyboardPreferenceKey.learnedWords,
        KeyboardPreferenceKey.learnedBigrams,
        KeyboardPreferenceKey.lastActive
    ]

    /// Ajustes del portapapeles que también usa el teclado al capturar.
    private static let clipboardKeys: Set<String> = [
        SharedClipboardStore.automaticCaptureKey,
        SharedClipboardStore.sensitiveModeKey,
        "skipOneTimeCodes",
        "temporaryRetentionHours",
        "maximumTemporaryItems"
    ]

    static func isTransferable(_ key: String) -> Bool {
        guard !excludedKeys.contains(key) else { return false }
        return key.hasPrefix("keyboard") || clipboardKeys.contains(key)
    }

    /// Los ajustes guardados en la app (solo los que se han cambiado alguna vez).
    static func payload(from defaults: UserDefaults?) -> Data? {
        guard let defaults else { return nil }
        let values = defaults.dictionaryRepresentation().filter { isTransferable($0.key) }
        guard !values.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    /// Guarda en el teclado los ajustes recibidos. Devuelve cuántos se aplicaron.
    @discardableResult
    static func apply(_ data: Data, to defaults: UserDefaults?) -> Int {
        guard let defaults,
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return 0 }
        var applied = 0
        for (key, value) in values where isTransferable(key) {
            defaults.set(value, forKey: key)
            applied += 1
        }
        return applied
    }
}
