import Foundation
import TableProPluginKit

// MARK: - ChartSpecInferrer

enum ChartSpecInferrer {
    // MARK: Internal

    enum ColumnKind {
        case numeric
        case temporal
        case category
        case unsupported
    }

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

    static func isNumericColumn(at ordinal: Int, in tableRows: TableRows) -> Bool {
        kind(at: ordinal, in: tableRows) == .numeric
    }

    static func kind(at ordinal: Int, in tableRows: TableRows) -> ColumnKind {
        guard ordinal < tableRows.columnTypes.count else {
            return sampledKind(at: ordinal, in: tableRows)
        }

        switch tableRows.columnTypes[ordinal] {
        case .integer,
             .decimal:
            return .numeric
        case .date,
             .timestamp,
             .datetime:
            return .temporal
        case .text,
             .enumType:
            return .category
        default:
            return .unsupported
        }
    }

    // MARK: Private

    private static let numericLocale = Locale(identifier: "en_US_POSIX")

    private static func sampledKind(at ordinal: Int, in tableRows: TableRows) -> ColumnKind {
        let values = tableRows.rows.prefix(50).compactMap { row in
            row.values[ordinal].asText?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !values.isEmpty else {
            return .unsupported
        }

        if values.allSatisfy({ ChartDateParser.parse($0) != nil }) {
            return .temporal
        }
        if values.allSatisfy({ Decimal(string: $0, locale: numericLocale) != nil }) {
            return .numeric
        }
        return .category
    }
}
