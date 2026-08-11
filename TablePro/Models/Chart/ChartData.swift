import Foundation

enum ChartXValue: Equatable, Sendable {
    case category(String)
    case number(Double)
    case date(Date)
}

struct ChartPoint: Identifiable, Equatable, Sendable {
    let id: String
    let sourceRow: Int
    let x: ChartXValue
    let y: Double
    let series: String
}

struct ChartData: Equatable, Sendable {
    let points: [ChartPoint]
    let skippedValueCount: Int
    let isSampled: Bool
}

enum ChartDataBuilderError: Error, Equatable {
    case invalidSpecification
}
