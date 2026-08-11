import Foundation
import TableProPluginKit

enum ChartDataBuilder {
    static let defaultPointLimit = 5_000

    static func build(
        from tableRows: TableRows,
        spec: ChartSpec,
        limit: Int = defaultPointLimit
    ) throws -> ChartData {
        guard let validSpec = spec.validated(for: tableRows) else {
            throw ChartDataBuilderError.invalidSpecification
        }
        let built = buildAllPoints(from: tableRows, spec: validSpec)
        let sorted = sort(built.points, order: validSpec.sortOrder)
        let sampled = sample(sorted, limit: limit)
        return ChartData(
            points: sampled,
            skippedValueCount: built.skipped,
            isSampled: sampled.count < sorted.count
        )
    }

    private static func buildAllPoints(
        from tableRows: TableRows,
        spec: ChartSpec
    ) -> (points: [ChartPoint], skipped: Int) {
        var points: [ChartPoint] = []
        var skipped = 0

        for (rowIndex, row) in tableRows.rows.enumerated() {
            let x = parseX(
                row.values[spec.xColumn.ordinal].asText,
                type: tableRows.columnTypes[safe: spec.xColumn.ordinal]
            )
            let explicitSeries = spec.seriesColumn.flatMap { row.values[$0.ordinal].asText }

            for yColumn in spec.yColumns {
                guard let yText = row.values[yColumn.ordinal].asText,
                      let y = Double(yText) else {
                    skipped += 1
                    continue
                }

                let series = explicitSeries ?? yColumn.name
                points.append(ChartPoint(
                    id: "row:\(rowIndex):y:\(yColumn.ordinal):series:\(series)",
                    sourceRow: rowIndex,
                    x: x,
                    y: y,
                    series: series
                ))
            }
        }

        return (points, skipped)
    }

    private static func parseX(_ text: String?, type: ColumnType?) -> ChartXValue {
        let value = text ?? ""
        switch type {
        case .integer, .decimal:
            return Double(value).map(ChartXValue.number) ?? .category(value)
        case .date, .timestamp, .datetime:
            return parseDate(value).map(ChartXValue.date) ?? .category(value)
        default:
            return .category(value)
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func sort(_ points: [ChartPoint], order: ChartSortOrder) -> [ChartPoint] {
        switch order {
        case .source:
            return points
        case .ascendingX:
            return sortByX(points, ascending: true)
        case .descendingX:
            return sortByX(points, ascending: false)
        }
    }

    private static func sortByX(_ points: [ChartPoint], ascending: Bool) -> [ChartPoint] {
        points.enumerated().sorted { left, right in
            let result = compare(left.element.x, right.element.x)
            if result == .orderedSame {
                return left.offset < right.offset
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }.map(\.element)
    }

    private static func compare(_ lhs: ChartXValue, _ rhs: ChartXValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (.number(left), .number(right)):
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case let (.date(left), .date(right)):
            return left.compare(right)
        case let (.category(left), .category(right)):
            return left.compare(right, options: .literal)
        default:
            return xSortKey(lhs).compare(xSortKey(rhs), options: .literal)
        }
    }

    private static func xSortKey(_ value: ChartXValue) -> String {
        switch value {
        case .category(let value):
            return "0:\(value)"
        case .number(let value):
            return "1:\(value)"
        case .date(let value):
            return "2:\(value.timeIntervalSinceReferenceDate)"
        }
    }

    private static func sample(_ points: [ChartPoint], limit: Int) -> [ChartPoint] {
        guard limit > 0, points.count > limit else { return limit > 0 ? points : [] }
        return (0..<limit).map { index in
            let sampledIndex = Int(round(Double(index) * Double(points.count - 1) / Double(limit - 1)))
            return points[sampledIndex]
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
