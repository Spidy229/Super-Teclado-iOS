import Foundation

enum ClipboardRetentionPolicy {
    static let defaultTemporaryHours = 24
    static let defaultMaximumTemporaryItems = 50

    static func expirationDate(
        hours: Int,
        from date: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard hours > 0 else { return nil }
        return calendar.date(byAdding: .hour, value: hours, to: date)
    }

    static func isExpired(
        isTemporary: Bool,
        expiresAt: Date?,
        at date: Date = .now
    ) -> Bool {
        isTemporary && expiresAt.map { $0 <= date } == true
    }
}
