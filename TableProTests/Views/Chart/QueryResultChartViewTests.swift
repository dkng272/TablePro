import SwiftUI
import TableProPluginKit
import Testing
@testable import TablePro

@MainActor
@Suite("QueryResultChartView")
struct QueryResultChartViewTests {
    @Test("Empty results select the no-rows state")
    func emptyResults() {
        #expect(QueryResultChartState.resolve(tableRows: TableRows(), storedSpec: nil) == .noRows)
    }

    @Test("Compatible results select an inferred chart")
    func inferredChart() {
        let rows = TableRows.from(
            queryRows: [["Q1", "10"]],
            columns: ["quarter", "revenue"],
            columnTypes: [.text(rawType: nil), .decimal(rawType: nil)]
        )
        let state = QueryResultChartState.resolve(tableRows: rows, storedSpec: nil)
        guard case .configured(let spec) = state else {
            Issue.record("Expected configured chart state")
            return
        }
        #expect(spec.chartType == .bar)
    }

    @Test("The chart view can be constructed")
    func viewConstruction() {
        let view = QueryResultChartView(tableRows: TableRows(), spec: .constant(nil))
        #expect(type(of: view.body) != Never.self)
    }
}
