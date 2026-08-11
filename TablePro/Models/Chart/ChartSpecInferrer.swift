import Foundation
import TableProPluginKit

enum ChartSpecInferrer {
    static func infer(from tableRows: TableRows) -> ChartSpec? {
        let columns = tableRows.columns.enumerated().map {
            ChartColumnID(ordinal: $0.offset, name: $0.element)
        }
        let kinds = columns.map { kind(at: $0.ordinal, in: tableRows) }
        let numeric = columns.filter { kinds[$0.ordinal] == .numeric }

        if let date = columns.first(where: { kinds[$0.ordinal] == .temporal }), !numeric.isEmpty {
            return ChartSpec(chartType: .line, xColumn: date, yColumns: numeric)
        }
        if let category = columns.first(where: { kinds[$0.ordinal] == .category }), !numeric.isEmpty {
            return ChartSpec(chartType: .bar, xColumn: category, yColumns: numeric)
        }
        if numeric.count >= 2 {
            return ChartSpec(chartType: .scatter, xColumn: numeric[0], yColumns: [numeric[1]])
        }
        return nil
    }

    private enum Kind {
        case numeric
        case temporal
        case category
        case unsupported
    }

    private static func kind(at ordinal: Int, in tableRows: TableRows) -> Kind {
        guard ordinal < tableRows.columnTypes.count else {
            return sampledKind(at: ordinal, in: tableRows)
        }

        switch tableRows.columnTypes[ordinal] {
        case .integer, .decimal:
            return .numeric
        case .date, .timestamp, .datetime:
            return .temporal
        case .text, .enumType:
            return .category
        default:
            return .unsupported
        }
    }

    private static func sampledKind(at ordinal: Int, in tableRows: TableRows) -> Kind {
        let values = tableRows.rows.prefix(50).compactMap { row in
            row.values[ordinal].asText?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !values.isEmpty else { return .unsupported }

        if values.allSatisfy({ Decimal(string: $0) != nil }) {
            return .numeric
        }
        if values.allSatisfy(isISO8601Date) {
            return .temporal
        }
        return .category
    }

    private static func isISO8601Date(_ value: String) -> Bool {
        ISO8601DateFormatter().date(from: value) != nil
            || DateFormatter.iso8601Date.date(from: value) != nil
    }
}

private extension DateFormatter {
    static let iso8601Date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
