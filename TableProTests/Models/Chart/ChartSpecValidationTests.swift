@testable import TablePro
import TableProPluginKit
import Testing

@Suite("ChartSpec validation")
struct ChartSpecValidationTests {
    @Test("Validation removes missing Y and series columns")
    func removesMissingColumns() throws {
        let original = ChartSpec(
            chartType: .line,
            xColumn: .init(ordinal: 0, name: "month"),
            yColumns: [.init(ordinal: 1, name: "revenue"), .init(ordinal: 2, name: "margin")],
            seriesColumn: .init(ordinal: 3, name: "region"),
            title: "Performance"
        )
        let rows = TableRows.from(
            queryRows: [["2026-01-01", "10"]],
            columns: ["month", "revenue"],
            columnTypes: [.date(rawType: nil), .decimal(rawType: nil)]
        )

        let repaired = try #require(original.validated(for: rows))
        #expect(repaired.yColumns.map(\.name) == ["revenue"])
        #expect(repaired.seriesColumn == nil)
    }

    @Test("Validation rejects a missing X column")
    func missingXReturnsNil() {
        let original = ChartSpec(
            chartType: .bar,
            xColumn: .init(ordinal: 8, name: "missing"),
            yColumns: [.init(ordinal: 1, name: "revenue")]
        )
        let rows = TableRows(columns: ["region", "revenue"])
        #expect(original.validated(for: rows) == nil)
    }
}
