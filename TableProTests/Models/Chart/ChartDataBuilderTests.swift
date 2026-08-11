import TableProPluginKit
import Testing
@testable import TablePro

@Suite("ChartDataBuilder")
struct ChartDataBuilderTests {
    @Test("Build skips null and malformed Y values")
    func skipsInvalidValues() throws {
        let rows = Self.rows(
            values: [["2026-01-01", "10"], ["2026-02-01", nil], ["2026-03-01", "bad"]],
            columns: ["month", "revenue"],
            types: [.date(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .line,
            xColumn: .init(ordinal: 0, name: "month"),
            yColumns: [.init(ordinal: 1, name: "revenue")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.count == 1)
        #expect(data.points[0].y == 10)
        #expect(data.skippedValueCount == 2)
    }

    @Test("Multiple Y columns become separate stable series")
    func multipleYColumnsBecomeSeries() throws {
        let rows = Self.rows(
            values: [["Q1", "10", "4"]],
            columns: ["quarter", "revenue", "margin"],
            types: [.text(rawType: nil), .decimal(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .bar,
            xColumn: .init(ordinal: 0, name: "quarter"),
            yColumns: [.init(ordinal: 1, name: "revenue"), .init(ordinal: 2, name: "margin")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)
        #expect(data.points.map(\.series) == ["revenue", "margin"])
    }

    @Test("Ascending X sort orders numeric values")
    func ascendingNumericSort() throws {
        let rows = Self.rows(
            values: [["2", "20"], ["1", "10"]],
            columns: ["x", "y"],
            types: [.integer(rawType: nil), .integer(rawType: nil)]
        )
        var spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )
        spec.sortOrder = .ascendingX

        let data = try ChartDataBuilder.build(from: rows, spec: spec)
        #expect(data.points.map(\.x) == [.number(1), .number(2)])
    }

    @Test("Explicit series column labels each point")
    func explicitSeriesLabelsPoints() throws {
        let rows = Self.rows(
            values: [["Q1", "10", "North"], ["Q1", "12", "South"]],
            columns: ["quarter", "revenue", "region"],
            types: [.text(rawType: nil), .decimal(rawType: nil), .text(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .bar,
            xColumn: .init(ordinal: 0, name: "quarter"),
            yColumns: [.init(ordinal: 1, name: "revenue")],
            seriesColumn: .init(ordinal: 2, name: "region")
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)
        #expect(data.points.map(\.series) == ["North", "South"])
    }

    @Test("SQL date text parses as temporal X values")
    func sqlDateParsing() throws {
        let rows = Self.rows(
            values: [["2026-01-01 12:30:00", "10"]],
            columns: ["created_at", "revenue"],
            types: [.datetime(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .line,
            xColumn: .init(ordinal: 0, name: "created_at"),
            yColumns: [.init(ordinal: 1, name: "revenue")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)
        guard case .date = data.points.first?.x else {
            Issue.record("Expected parsed date X value")
            return
        }
    }

    @Test("Sampling is deterministic and preserves endpoints")
    func samplingPreservesEndpoints() throws {
        let values: [[String?]] = (0..<5_001).map { [String($0), String($0 * 2)] }
        let rows = Self.rows(
            values: values,
            columns: ["x", "y"],
            types: [.integer(rawType: nil), .integer(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )

        let first = try ChartDataBuilder.build(from: rows, spec: spec)
        let second = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(first.points.count == 5_000)
        #expect(first.points.first?.x == .number(0))
        #expect(first.points.last?.x == .number(5_000))
        #expect(first.points.map(\.id) == second.points.map(\.id))
        #expect(first.isSampled)
    }

    @Test("Caller limit cannot exceed the chart point cap")
    func callerLimitIsClampedToDefaultCap() throws {
        let values: [[String?]] = (0..<5_001).map { [String($0), String($0 * 2)] }
        let rows = Self.rows(
            values: values,
            columns: ["x", "y"],
            types: [.integer(rawType: nil), .integer(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec, limit: 10_000)

        #expect(data.points.count == 5_000)
        #expect(data.isSampled)
    }

    @Test("One-point sampling retains the first point")
    func onePointSamplingRetainsFirstPoint() throws {
        let rows = Self.rows(
            values: [["0", "0"], ["1", "2"]],
            columns: ["x", "y"],
            types: [.integer(rawType: nil), .integer(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec, limit: 1)

        #expect(data.points.count == 1)
        #expect(data.points.first?.x == .number(0))
        #expect(data.isSampled)
    }

    private static func rows(
        values: [[String?]], columns: [String], types: [ColumnType]
    ) -> TableRows {
        TableRows.from(
            queryRows: values.map { $0.map(PluginCellValue.fromOptional) },
            columns: columns,
            columnTypes: types
        )
    }
}
