import Foundation

// MARK: - ChartXValue

enum ChartXValue: Equatable, Sendable {
    case category(String)
    case number(Double)
    case date(Date)
}

// MARK: - ChartPoint

struct ChartPoint: Identifiable, Equatable, Sendable {
    let id: String
    let sourceRow: Int
    let x: ChartXValue
    let y: Double
    let seriesID: String
    let seriesLabel: String
}

// MARK: - ChartData

struct ChartData: Equatable, Sendable {
    let points: [ChartPoint]
    let skippedValueCount: Int
    let isSampled: Bool
}

// MARK: - ChartDataBuilderError

enum ChartDataBuilderError: Error, Equatable {
    case invalidSpecification
}
