import Foundation
import TableProPluginKit

// MARK: - ChartDataBuilder

enum ChartDataBuilder {
    // MARK: Internal

    static let defaultPointLimit = 5000

    static func build(
        from tableRows: TableRows,
        spec: ChartSpec,
        limit: Int = defaultPointLimit
    )
        throws -> ChartData
    {
        guard let validSpec = spec.validated(for: tableRows) else {
            throw ChartDataBuilderError.invalidSpecification
        }
        let built = buildAllPoints(from: tableRows, spec: validSpec)
        let sorted = sort(built.points, order: validSpec.sortOrder)
        let sampled = sample(sorted, limit: min(limit, defaultPointLimit))
        return ChartData(
            points: sampled,
            skippedValueCount: built.skipped,
            isSampled: sampled.count < sorted.count
        )
    }

    // MARK: Private

    private struct SeriesGroup {
        let id: String
        let order: Int
        let pointIndices: [Int]
    }

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

    private static func buildAllPoints(
        from tableRows: TableRows,
        spec: ChartSpec
    )
        -> (points: [ChartPoint], skipped: Int)
    {
        var points: [ChartPoint] = []
        var skipped = 0
        let xKind = ChartSpecInferrer.kind(at: spec.xColumn.ordinal, in: tableRows)
        let yNameCounts = Dictionary(grouping: spec.yColumns, by: \.name).mapValues(\.count)
        let measureLabels = Dictionary(uniqueKeysWithValues: spec.yColumns.map { column in
            let label = yNameCounts[column.name, default: 0] > 1
                ? "\(column.name) (\(column.ordinal + 1))"
                : column.name
            return (column, label)
        })

        for (rowIndex, row) in tableRows.rows.enumerated() {
            guard let x = parseX(
                row.values[spec.xColumn.ordinal].asText,
                kind: xKind
            ) else {
                skipped += spec.yColumns.count
                continue
            }
            let explicitSeriesValue = spec.seriesColumn.flatMap { row.values[$0.ordinal].asText }

            for yColumn in spec.yColumns {
                guard let yText = row.values[yColumn.ordinal].asText,
                      let y = parseFiniteDouble(yText) else
                {
                    skipped += 1
                    continue
                }

                let measureLabel = measureLabels[yColumn, default: yColumn.name]
                let seriesID = makeSeriesID(
                    measure: yColumn,
                    groupColumn: spec.seriesColumn,
                    groupValue: explicitSeriesValue
                )
                let seriesLabel = makeSeriesLabel(
                    measure: measureLabel,
                    measureCount: spec.yColumns.count,
                    groupColumn: spec.seriesColumn,
                    groupValue: explicitSeriesValue
                )
                points.append(ChartPoint(
                    id: "row:\(rowIndex):series:\(seriesID)",
                    sourceRow: rowIndex,
                    x: x,
                    y: y,
                    seriesID: seriesID,
                    seriesLabel: seriesLabel
                ))
            }
        }

        return (points, skipped)
    }

    private static func makeSeriesID(
        measure: ChartColumnID,
        groupColumn: ChartColumnID?,
        groupValue: String?
    )
        -> String
    {
        let measureComponent = lengthPrefixed(measure.id)
        guard let groupColumn else {
            return "measure:\(measureComponent)"
        }
        let groupComponent = groupValue.map { "value:\(lengthPrefixed($0))" } ?? "null"
        return "measure:\(measureComponent):group:\(lengthPrefixed(groupColumn.id)):\(groupComponent)"
    }

    private static func makeSeriesLabel(
        measure: String,
        measureCount: Int,
        groupColumn: ChartColumnID?,
        groupValue: String?
    )
        -> String
    {
        guard groupColumn != nil else {
            return measure
        }
        let group = groupValue ?? String(localized: "NULL")
        guard measureCount > 1 else {
            return group
        }
        return String(format: String(localized: "%@ by %@"), measure, group)
    }

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    private static func parseX(
        _ text: String?,
        kind: ChartSpecInferrer.ColumnKind
    )
        -> ChartXValue?
    {
        guard let value = text else {
            return nil
        }

        switch kind {
        case .numeric:
            return parseFiniteDouble(value).map(ChartXValue.number)
        case .temporal:
            return parseDate(value).map(ChartXValue.date)
        case .category,
             .unsupported:
            return .category(value)
        }
    }

    private static func parseFiniteDouble(_ value: String) -> Double? {
        guard let parsed = Double(value), parsed.isFinite else {
            return nil
        }
        return parsed
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = iso8601DateFormatter.date(from: value) {
            return date
        }
        return sqlDateFormatters.lazy.compactMap { $0.date(from: value) }.first
    }

    private static func sort(_ points: [ChartPoint], order: ChartSortOrder) -> [ChartPoint] {
        switch order {
        case .source:
            points
        case .ascendingX:
            sortByX(points, ascending: true)
        case .descendingX:
            sortByX(points, ascending: false)
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
            left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case let (.date(left), .date(right)):
            left.compare(right)
        case let (.category(left), .category(right)):
            left.compare(right, options: .literal)
        default:
            xSortKey(lhs).compare(xSortKey(rhs), options: .literal)
        }
    }

    private static func xSortKey(_ value: ChartXValue) -> String {
        switch value {
        case let .category(value):
            "0:\(value)"
        case let .number(value):
            "1:\(value)"
        case let .date(value):
            "2:\(value.timeIntervalSinceReferenceDate)"
        }
    }

    private static func sample(_ points: [ChartPoint], limit: Int) -> [ChartPoint] {
        guard limit > 0, points.count > limit else {
            return limit > 0 ? points : []
        }
        if limit == 1 {
            return [points[0]]
        }

        let groups = orderedSeriesGroups(in: points)
        let retainedGroups = retainedSeriesGroups(groups, limit: limit)
        let quotas = proportionalQuotas(for: retainedGroups, limit: limit)
        var retainedPointIndices = Set<Int>()

        for group in retainedGroups {
            let quota = quotas[group.id, default: 0]
            retainedPointIndices.formUnion(sample(group.pointIndices, limit: quota))
        }

        return points.enumerated().compactMap { index, point in
            retainedPointIndices.contains(index) ? point : nil
        }
    }

    private static func orderedSeriesGroups(in points: [ChartPoint]) -> [SeriesGroup] {
        var seriesOrder: [String] = []
        var pointIndicesBySeries: [String: [Int]] = [:]

        for (index, point) in points.enumerated() {
            if pointIndicesBySeries[point.seriesID] == nil {
                seriesOrder.append(point.seriesID)
            }
            pointIndicesBySeries[point.seriesID, default: []].append(index)
        }

        return seriesOrder.enumerated().map { order, seriesID in
            SeriesGroup(
                id: seriesID,
                order: order,
                pointIndices: pointIndicesBySeries[seriesID, default: []]
            )
        }
    }

    private static func retainedSeriesGroups(
        _ groups: [SeriesGroup],
        limit: Int
    )
        -> [SeriesGroup]
    {
        let minimumRequired = groups.reduce(0) { $0 + min($1.pointIndices.count, 2) }
        guard minimumRequired > limit else {
            return groups
        }

        var remaining = limit
        return groups.filter { group in
            let minimum = min(group.pointIndices.count, 2)
            guard minimum <= remaining else {
                return false
            }
            remaining -= minimum
            return true
        }
    }

    private static func proportionalQuotas(
        for groups: [SeriesGroup],
        limit: Int
    )
        -> [String: Int]
    {
        var quotas = Dictionary(uniqueKeysWithValues: groups.map {
            ($0.id, min($0.pointIndices.count, 2))
        })
        let assignedMinimums = quotas.values.reduce(0, +)
        let residualCounts = groups.map { max(0, $0.pointIndices.count - quotas[$0.id, default: 0]) }
        let totalResidual = residualCounts.reduce(0, +)
        let availableSlots = min(limit - assignedMinimums, totalResidual)
        guard availableSlots > 0, totalResidual > 0 else {
            return quotas
        }

        var remainders: [(group: SeriesGroup, fraction: Double)] = []
        var assignedResidual = 0
        for (group, residualCount) in zip(groups, residualCounts) {
            let exact = Double(availableSlots) * Double(residualCount) / Double(totalResidual)
            let allocation = Int(exact.rounded(.down))
            quotas[group.id, default: 0] += allocation
            assignedResidual += allocation
            remainders.append((group, exact - Double(allocation)))
        }

        let extraSlots = availableSlots - assignedResidual
        let remainderOrder = remainders.sorted { left, right in
            if left.fraction == right.fraction {
                return left.group.order < right.group.order
            }
            return left.fraction > right.fraction
        }
        for remainder in remainderOrder.prefix(extraSlots) {
            quotas[remainder.group.id, default: 0] += 1
        }
        return quotas
    }

    private static func sample(_ indices: [Int], limit: Int) -> [Int] {
        guard limit > 0, indices.count > limit else {
            return limit > 0 ? indices : []
        }
        if limit == 1 {
            return [indices[0]]
        }
        return (0 ..< limit).map { index in
            let sampledIndex = Int(round(Double(index) * Double(indices.count - 1) / Double(limit - 1)))
            return indices[sampledIndex]
        }
    }
}
