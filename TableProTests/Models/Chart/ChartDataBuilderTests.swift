@testable import TablePro
import TableProPluginKit
import Testing

@Suite("ChartDataBuilder")
struct ChartDataBuilderTests {
    // MARK: Internal

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

    @Test("Null X skips one attempted point per Y column")
    func nullXSkipsEachSeriesPoint() throws {
        let rows = Self.rows(
            values: [[nil, "10", "4"], ["Q1", "12", "5"]],
            columns: ["quarter", "revenue", "margin"],
            types: [.text(rawType: nil), .decimal(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .bar,
            xColumn: .init(ordinal: 0, name: "quarter"),
            yColumns: [.init(ordinal: 1, name: "revenue"), .init(ordinal: 2, name: "margin")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.map(\.x) == [.category("Q1"), .category("Q1")])
        #expect(data.skippedValueCount == 2)
    }

    @Test("Malformed numeric X is skipped")
    func malformedNumericXIsSkipped() throws {
        let rows = Self.rows(
            values: [["bad", "10"], ["2", "12"]],
            columns: ["x", "y"],
            types: [.integer(rawType: nil), .integer(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.map(\.x) == [.number(2)])
        #expect(data.skippedValueCount == 1)
    }

    @Test("Malformed date X is skipped")
    func malformedDateXIsSkipped() throws {
        let rows = Self.rows(
            values: [["bad-date", "10"], ["2026-01-01", "12"]],
            columns: ["day", "y"],
            types: [.date(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .line,
            xColumn: .init(ordinal: 0, name: "day"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.count == 1)
        guard case .date = data.points.first?.x else {
            Issue.record("Expected the valid date X value to remain")
            return
        }
        #expect(data.skippedValueCount == 1)
    }

    @Test("Inferred numeric X stays numeric and sorts when metadata is short")
    func inferredNumericXStaysNumeric() throws {
        let rows = Self.rows(
            values: [["ignored", "20", "2"], ["ignored", "3", "1"]],
            columns: ["flag", "price", "volume"],
            types: [.boolean(rawType: nil)]
        )
        var spec = try #require(ChartSpecInferrer.infer(from: rows))
        spec.sortOrder = .ascendingX

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(spec.chartType == .scatter)
        #expect(data.points.map(\.x) == [.number(3), .number(20)])
    }

    @Test("Inferred date X stays temporal and sorts when metadata is short")
    func inferredDateXStaysTemporal() throws {
        let rows = Self.rows(
            values: [
                ["ignored", "2026-02-01", "20"],
                ["ignored", "2026-01-01", "10"],
            ],
            columns: ["flag", "month", "revenue"],
            types: [.boolean(rawType: nil)]
        )
        var spec = try #require(ChartSpecInferrer.infer(from: rows))
        spec.sortOrder = .ascendingX

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(spec.chartType == .line)
        #expect(data.points.map(\.sourceRow) == [1, 0])
        #expect(data.points.allSatisfy {
            if case .date = $0.x {
                true
            } else {
                false
            }
        })
    }

    @Test("Non-finite numeric X and Y values are skipped")
    func nonFiniteNumericValuesAreSkipped() throws {
        let rows = Self.rows(
            values: [["nan", "10"], ["2", "inf"], ["3", "30"]],
            columns: ["x", "y"],
            types: [.decimal(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.map(\.x) == [.number(3)])
        #expect(data.points.map(\.y) == [30])
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
        #expect(data.points.map(\.seriesLabel) == ["revenue", "margin"])
    }

    @Test("Duplicate Y names have distinct stable series and readable labels")
    func duplicateYNamesRemainDistinct() throws {
        let rows = Self.rows(
            values: [["Q1", "10", "4"]],
            columns: ["quarter", "value", "value"],
            types: [.text(rawType: nil), .decimal(rawType: nil), .decimal(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .bar,
            xColumn: .init(ordinal: 0, name: "quarter"),
            yColumns: [.init(ordinal: 1, name: "value"), .init(ordinal: 2, name: "value")]
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.map(\.seriesLabel) == ["value (2)", "value (3)"])
        #expect(Set(data.points.map(\.seriesID)).count == 2)
        #expect(Set(data.points.map(\.id)).count == 2)
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
        #expect(data.points.map(\.seriesLabel) == ["North", "South"])
    }

    @Test("Explicit groups and multiple Y columns use composite series identity")
    func explicitGroupsWithMultipleMeasuresRemainDistinct() throws {
        let rows = Self.rows(
            values: [["Q1", "10", "4", "North"], ["Q1", "12", "5", "South"]],
            columns: ["quarter", "revenue", "margin", "region"],
            types: [
                .text(rawType: nil),
                .decimal(rawType: nil),
                .decimal(rawType: nil),
                .text(rawType: nil),
            ]
        )
        let spec = ChartSpec(
            chartType: .bar,
            xColumn: .init(ordinal: 0, name: "quarter"),
            yColumns: [
                .init(ordinal: 1, name: "revenue"),
                .init(ordinal: 2, name: "margin"),
            ],
            seriesColumn: .init(ordinal: 3, name: "region")
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)

        #expect(data.points.map(\.seriesLabel) == [
            "revenue by North", "margin by North",
            "revenue by South", "margin by South",
        ])
        #expect(Set(data.points.map(\.seriesID)).count == 4)
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
        let values: [[String?]] = (0 ..< 5001).map { [String($0), String($0 * 2)] }
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

        #expect(first.points.count == 5000)
        #expect(first.points.first?.x == .number(0))
        #expect(first.points.last?.x == .number(5000))
        #expect(first.points.map(\.id) == second.points.map(\.id))
        #expect(first.isSampled)
    }

    @Test("Interleaved series receive deterministic stratified samples")
    func samplingIsStratifiedAcrossInterleavedSeries() throws {
        let values: [[String?]] = (0 ..< 5000).map {
            [String($0), String($0 * 2), String($0 * 3)]
        }
        let rows = Self.rows(
            values: values,
            columns: ["x", "alpha", "beta"],
            types: [.integer(rawType: nil), .integer(rawType: nil), .integer(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "alpha"), .init(ordinal: 2, name: "beta")]
        )

        let first = try ChartDataBuilder.build(from: rows, spec: spec)
        let second = try ChartDataBuilder.build(from: rows, spec: spec)
        let alpha = first.points.filter { $0.seriesLabel == "alpha" }
        let beta = first.points.filter { $0.seriesLabel == "beta" }

        #expect(first.points.count == 5000)
        #expect(alpha.count == 2500)
        #expect(beta.count == 2500)
        #expect(alpha.map(\.sourceRow).first == 0)
        #expect(alpha.map(\.sourceRow).last == 4999)
        #expect(beta.map(\.sourceRow).first == 0)
        #expect(beta.map(\.sourceRow).last == 4999)
        #expect(first.points.map(\.id) == second.points.map(\.id))
    }

    @Test("Stratified sampling assigns proportional series quotas")
    func samplingUsesProportionalSeriesQuotas() throws {
        let values: [[String?]] = (0 ..< 9000).map { index in
            [String(index), String(index), index % 3 == 2 ? "Beta" : "Alpha"]
        }
        let rows = Self.rows(
            values: values,
            columns: ["x", "y", "series"],
            types: [.integer(rawType: nil), .integer(rawType: nil), .text(rawType: nil)]
        )
        let spec = ChartSpec(
            chartType: .scatter,
            xColumn: .init(ordinal: 0, name: "x"),
            yColumns: [.init(ordinal: 1, name: "y")],
            seriesColumn: .init(ordinal: 2, name: "series")
        )

        let data = try ChartDataBuilder.build(from: rows, spec: spec)
        let counts = Dictionary(grouping: data.points, by: \.seriesLabel).mapValues(\.count)

        #expect(data.points.count == 5000)
        #expect(counts == ["Alpha": 3333, "Beta": 1667])
        #expect(data.points.filter { $0.seriesLabel == "Alpha" }.map(\.sourceRow).first == 0)
        #expect(data.points.filter { $0.seriesLabel == "Alpha" }.map(\.sourceRow).last == 8998)
        #expect(data.points.filter { $0.seriesLabel == "Beta" }.map(\.sourceRow).first == 2)
        #expect(data.points.filter { $0.seriesLabel == "Beta" }.map(\.sourceRow).last == 8999)
    }

    @Test("Caller limit cannot exceed the chart point cap")
    func callerLimitIsClampedToDefaultCap() throws {
        let values: [[String?]] = (0 ..< 5001).map { [String($0), String($0 * 2)] }
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

        let data = try ChartDataBuilder.build(from: rows, spec: spec, limit: 10000)

        #expect(data.points.count == 5000)
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

    // MARK: Private

    private static func rows(
        values: [[String?]], columns: [String], types: [ColumnType]
    )
        -> TableRows
    {
        TableRows.from(
            queryRows: values.map { $0.map(PluginCellValue.fromOptional) },
            columns: columns,
            columnTypes: types
        )
    }
}
