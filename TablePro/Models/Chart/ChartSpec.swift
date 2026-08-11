import Foundation

// MARK: - ChartColumnID

struct ChartColumnID: Codable, Equatable, Hashable, Sendable, Identifiable {
    let ordinal: Int
    let name: String

    var id: String {
        "\(ordinal):\(name)"
    }
}

// MARK: - ChartType

enum ChartType: String, Codable, CaseIterable, Sendable {
    case line
    case bar
    case area
    case scatter

    // MARK: Internal

    var localizedName: String {
        switch self {
        case .line: String(localized: "Line")
        case .bar: String(localized: "Bar")
        case .area: String(localized: "Area")
        case .scatter: String(localized: "Scatter")
        }
    }
}

// MARK: - ChartSortOrder

enum ChartSortOrder: String, Codable, CaseIterable, Sendable {
    case source
    case ascendingX
    case descendingX
}

// MARK: - ChartSpec

struct ChartSpec: Codable, Equatable, Sendable {
    var chartType: ChartType
    var xColumn: ChartColumnID
    var yColumns: [ChartColumnID]
    var seriesColumn: ChartColumnID?
    var sortOrder: ChartSortOrder = .source
    var title: String = ""
    var showsLegend: Bool = true

    func validated(for tableRows: TableRows) -> ChartSpec? {
        let available = Set(tableRows.columns.enumerated().map {
            ChartColumnID(ordinal: $0.offset, name: $0.element)
        })
        guard available.contains(xColumn) else {
            return nil
        }
        var copy = self
        copy.yColumns = yColumns.filter(available.contains)
        guard !copy.yColumns.isEmpty else {
            return nil
        }
        if let seriesColumn, !available.contains(seriesColumn) {
            copy.seriesColumn = nil
        }
        return copy
    }
}
