import SwiftUI
@testable import TablePro
import TableProPluginKit
import Testing

// MARK: - QueryResultChartViewTests

@MainActor
@Suite("QueryResultChartView")
struct QueryResultChartViewTests {
    // MARK: Internal

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
        guard case let .configured(spec) = state else {
            Issue.record("Expected configured chart state")
            return
        }
        #expect(spec.chartType == .bar)
    }

    @Test("Removing the final Y column reconciles to an inferred spec")
    func removedFinalYReconciles() {
        let rows = Self.compatibleRows()
        let quarter = ChartColumnID(ordinal: 0, name: "quarter")
        let invalid = ChartSpec(chartType: .bar, xColumn: quarter, yColumns: [])

        let reconciled = QueryResultChartState.reconciledSpec(
            tableRows: rows,
            storedSpec: invalid
        )

        #expect(reconciled == ChartSpecInferrer.infer(from: rows))
    }

    @Test("An invalid stored spec requests persistence when the displayed spec is unchanged")
    func invalidStoredSpecRequestsPersistence() {
        let rows = Self.compatibleRows()
        let quarter = ChartColumnID(ordinal: 0, name: "quarter")
        let invalid = ChartSpec(chartType: .bar, xColumn: quarter, yColumns: [])
        guard let displayed = ChartSpecInferrer.infer(from: rows) else {
            Issue.record("Expected an inferred chart spec")
            return
        }

        let reconciliation = QueryResultChartReconciliation(
            storedSpec: invalid,
            resolvedSpec: displayed
        )

        #expect(reconciliation.specToPersist == displayed)
    }

    @Test("A reconciled stored spec does not request another persistence update")
    func reconciledSpecDoesNotRequestPersistence() {
        let rows = Self.compatibleRows()
        guard let displayed = ChartSpecInferrer.infer(from: rows) else {
            Issue.record("Expected an inferred chart spec")
            return
        }

        let reconciliation = QueryResultChartReconciliation(
            storedSpec: displayed,
            resolvedSpec: displayed
        )

        #expect(reconciliation.specToPersist == nil)
    }

    @Test("A schema change reconciles a stored spec to available columns")
    func schemaChangeReconciles() {
        let rows = Self.compatibleRows()
        let quarter = ChartColumnID(ordinal: 0, name: "quarter")
        let revenue = ChartColumnID(ordinal: 1, name: "revenue")
        let removed = ChartColumnID(ordinal: 2, name: "removed")
        let stored = ChartSpec(
            chartType: .line,
            xColumn: quarter,
            yColumns: [revenue, removed],
            title: "Revenue"
        )

        let reconciled = QueryResultChartState.reconciledSpec(
            tableRows: rows,
            storedSpec: stored
        )

        #expect(reconciled?.yColumns == [revenue])
        #expect(reconciled?.title == "Revenue")
        #expect(reconciled != stored)
    }

    @Test("Selecting the only numeric Y as X rejects the change")
    func selectingOnlyNumericYAsXIsRejected() {
        let rows = Self.compatibleRows()
        let quarter = ChartColumnID(ordinal: 0, name: "quarter")
        let revenue = ChartColumnID(ordinal: 1, name: "revenue")
        let original = ChartSpec(chartType: .bar, xColumn: quarter, yColumns: [revenue])

        let updated = ChartConfigurationPolicy.selectX(
            revenue,
            in: original,
            tableRows: rows
        )

        #expect(updated == original)
        #expect(!updated.yColumns.contains(updated.xColumn))
    }

    @Test("Selecting a Y as X chooses another numeric column for Y")
    func selectingYAsXUsesAnotherNumericY() {
        let rows = TableRows.from(
            queryRows: [["Q1", "10", "3"]],
            columns: ["quarter", "revenue", "profit"],
            columnTypes: [
                .text(rawType: nil),
                .decimal(rawType: nil),
                .integer(rawType: nil),
            ]
        )
        let quarter = ChartColumnID(ordinal: 0, name: "quarter")
        let revenue = ChartColumnID(ordinal: 1, name: "revenue")
        let profit = ChartColumnID(ordinal: 2, name: "profit")
        let original = ChartSpec(chartType: .bar, xColumn: quarter, yColumns: [revenue])

        let updated = ChartConfigurationPolicy.selectX(
            revenue,
            in: original,
            tableRows: rows
        )

        #expect(updated.xColumn == revenue)
        #expect(updated.yColumns == [profit])
    }

    @Test("Selecting X uses sampled numeric Y values when metadata is short")
    func selectingXUsesSampledNumericY() {
        let rows = TableRows.from(
            queryRows: [
                ["Q1", "10.5", "3"],
                ["Q2", "12.0", "4"],
            ],
            columns: ["quarter", "revenue", "profit"],
            columnTypes: [.text(rawType: nil)]
        )
        let revenue = ChartColumnID(ordinal: 1, name: "revenue")
        let profit = ChartColumnID(ordinal: 2, name: "profit")
        guard let original = ChartSpecInferrer.infer(from: rows) else {
            Issue.record("Expected sampled values to infer a chart spec")
            return
        }

        let updated = ChartConfigurationPolicy.selectX(
            revenue,
            in: original,
            tableRows: rows
        )

        #expect(updated.xColumn == revenue)
        #expect(updated.yColumns == [profit])
    }

    @Test("Sort orders provide compact localized labels")
    func sortOrderLabels() {
        #expect(ChartSortOrder.allCases.map(\.localizedName) == [
            "Source Order",
            "X Ascending",
            "X Descending",
        ])
    }

    @Test("Chart controls and empty state are localized")
    func chartInterfaceIsLocalized() {
        let translations = [
            (
                localizedChartString("Chart Type", locale: "tr"),
                localizedChartString("No rows to chart", locale: "tr"),
                localizedChartString("Source Order", locale: "tr"),
                localizedChartString("Line", locale: "tr"),
                "Grafik Türü", "Grafiğe dönüştürülecek satır yok", "Kaynak Sırası", "Çizgi"
            ),
            (
                localizedChartString("Chart Type", locale: "vi"),
                localizedChartString("No rows to chart", locale: "vi"),
                localizedChartString("Source Order", locale: "vi"),
                localizedChartString("Line", locale: "vi"),
                "Loại biểu đồ", "Không có hàng để vẽ biểu đồ", "Thứ tự nguồn", "Đường"
            ),
            (
                localizedChartString("Chart Type", locale: "zh-Hans"),
                localizedChartString("No rows to chart", locale: "zh-Hans"),
                localizedChartString("Source Order", locale: "zh-Hans"),
                localizedChartString("Line", locale: "zh-Hans"),
                "图表类型", "没有可绘制的行", "源顺序", "折线"
            ),
            (
                localizedChartString("Chart Type", locale: "zh-Hant"),
                localizedChartString("No rows to chart", locale: "zh-Hant"),
                localizedChartString("Source Order", locale: "zh-Hant"),
                localizedChartString("Line", locale: "zh-Hant"),
                "圖表類型", "沒有可繪製的列", "來源順序", "折線"
            ),
        ]

        for translation in translations {
            #expect(translation.0 == translation.4)
            #expect(translation.1 == translation.5)
            #expect(translation.2 == translation.6)
            #expect(translation.3 == translation.7)
        }
    }

    @Test("Invalid chart data selects a recoverable configuration state")
    func invalidChartData() {
        let rows = Self.compatibleRows()
        let quarter = ChartColumnID(ordinal: 0, name: "quarter")
        let invalid = ChartSpec(chartType: .bar, xColumn: quarter, yColumns: [])

        let state = QueryResultChartDataState.resolve(tableRows: rows, spec: invalid)

        #expect(state == .invalidConfiguration)
    }

    @Test("The chart view can be constructed")
    func viewConstruction() {
        let view = QueryResultChartView(tableRows: TableRows(), spec: .constant(nil))
        #expect(type(of: view.body) != Never.self)
    }

    // MARK: Private

    private static func compatibleRows() -> TableRows {
        TableRows.from(
            queryRows: [["Q1", "10"]],
            columns: ["quarter", "revenue"],
            columnTypes: [.text(rawType: nil), .decimal(rawType: nil)]
        )
    }
}

private func localizedChartString(_ key: String, locale: String) -> String {
    guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
          let bundle = Bundle(path: path) else
    {
        return key
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}
