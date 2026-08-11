import Foundation

// MARK: - ChartDateParser

enum ChartDateParser {
    // MARK: Internal

    static func parse(_ value: String) -> Date? {
        if let date = iso8601DateFormatter.date(from: value) {
            return date
        }
        return sqlDateFormatters.lazy.compactMap { $0.date(from: value) }.first
    }

    // MARK: Private

    private static let iso8601DateFormatter = ISO8601DateFormatter()
    private static let sqlDateFormatters: [DateFormatter] = [
        "yyyy-MM-dd",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
