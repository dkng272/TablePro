@testable import TablePro
import TableProPluginKit
import Testing

@Suite("ChartSpecInferrer")
struct ChartSpecInferrerTests {
    @Test("Date plus numeric columns infer a line chart")
    func dateAndNumericInferLine() throws {
        let rows = TableRows.from(
            queryRows: [["2026-01-01", "10"], ["2026-02-01", "12"]],
            columns: ["month", "revenue"],
            columnTypes: [.date(rawType: "DATE"), .decimal(rawType: "DECIMAL")]
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))

        #expect(spec.chartType == .line)
        #expect(spec.xColumn == ChartColumnID(ordinal: 0, name: "month"))
        #expect(spec.yColumns == [ChartColumnID(ordinal: 1, name: "revenue")])
    }

    @Test("Category plus numeric columns infer a bar chart")
    func categoryAndNumericInferBar() throws {
        let rows = TableRows.from(
            queryRows: [["North", "10"], ["South", "12"]],
            columns: ["region", "revenue"],
            columnTypes: [.text(rawType: "VARCHAR"), .integer(rawType: "INT")]
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .bar)
        #expect(spec.xColumn.ordinal == 0)
        #expect(spec.yColumns.map(\.ordinal) == [1])
    }

    @Test("Two numeric columns infer a scatter chart")
    func numericColumnsInferScatter() throws {
        let rows = TableRows.from(
            queryRows: [["1", "10"], ["2", "12"]],
            columns: ["price", "volume"],
            columnTypes: [.decimal(rawType: nil), .integer(rawType: nil)]
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .scatter)
        #expect(spec.xColumn.ordinal == 0)
        #expect(spec.yColumns.map(\.ordinal) == [1])
    }

    @Test("Incompatible columns do not infer a chart")
    func incompatibleReturnsNil() {
        let rows = TableRows.from(
            queryRows: [["a", "b"]],
            columns: ["left", "right"],
            columnTypes: [.text(rawType: nil), .text(rawType: nil)]
        )

        #expect(ChartSpecInferrer.infer(from: rows) == nil)
    }

    @Test("Missing metadata samples dates as temporal columns")
    func missingMetadataSamplesDates() throws {
        let rows = TableRows.from(
            queryRows: [["2026-01-01", "10"], ["2026-02-01", "12"]],
            columns: ["month", "revenue"],
            columnTypes: []
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .line)
        #expect(spec.xColumn.ordinal == 0)
        #expect(spec.yColumns.map(\.ordinal) == [1])
    }

    @Test("Missing metadata samples text as category columns")
    func missingMetadataSamplesCategories() throws {
        let rows = TableRows.from(
            queryRows: [["North", "10"], ["South", "12"]],
            columns: ["region", "revenue"],
            columnTypes: []
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .bar)
        #expect(spec.xColumn.ordinal == 0)
        #expect(spec.yColumns.map(\.ordinal) == [1])
    }

    @Test("Missing metadata samples numeric columns")
    func missingMetadataSamplesNumericColumns() throws {
        let rows = TableRows.from(
            queryRows: [["1.5", "10.25"], ["2.5", "12.75"]],
            columns: ["price", "volume"],
            columnTypes: []
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .scatter)
        #expect(spec.xColumn.ordinal == 0)
        #expect(spec.yColumns.map(\.ordinal) == [1])
    }

    @Test("Missing metadata samples at most fifty rows")
    func missingMetadataSamplesAtMostFiftyRows() throws {
        let rows = TableRows.from(
            queryRows: (0 ..< 51).map { index in
                [index == 50 ? "not-a-number" : "1", "10"]
            },
            columns: ["price", "volume"],
            columnTypes: []
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .scatter)
    }

    @Test("Metadata takes precedence over sampled values")
    func metadataTakesPrecedenceOverSamples() throws {
        let rows = TableRows.from(
            queryRows: [["2026-01-01", "10"], ["2026-02-01", "12"]],
            columns: ["month", "revenue"],
            columnTypes: [.text(rawType: "VARCHAR"), .integer(rawType: "INT")]
        )

        let spec = try #require(ChartSpecInferrer.infer(from: rows))
        #expect(spec.chartType == .bar)
        #expect(spec.xColumn.ordinal == 0)
    }
}
