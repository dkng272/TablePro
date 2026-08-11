import Charts
import SwiftUI

// MARK: - QueryResultChartState

enum QueryResultChartState: Equatable {
    case noRows
    case needsConfiguration
    case configured(ChartSpec)

    // MARK: Internal

    static func resolve(tableRows: TableRows, storedSpec: ChartSpec?) -> Self {
        // swiftformat:disable:next isEmpty
        guard !tableRows.columns.isEmpty, tableRows.count > 0 else {
            return .noRows
        }
        if let storedSpec, let valid = storedSpec.validated(for: tableRows) {
            return .configured(valid)
        }
        if let inferred = ChartSpecInferrer.infer(from: tableRows) {
            return .configured(inferred)
        }
        return .needsConfiguration
    }

    static func reconciledSpec(tableRows: TableRows, storedSpec: ChartSpec?) -> ChartSpec? {
        guard case let .configured(spec) = resolve(tableRows: tableRows, storedSpec: storedSpec) else {
            return nil
        }
        return spec
    }
}

// MARK: - QueryResultChartReconciliation

struct QueryResultChartReconciliation: Equatable {
    let storedSpec: ChartSpec?
    let resolvedSpec: ChartSpec

    var specToPersist: ChartSpec? {
        storedSpec == resolvedSpec ? nil : resolvedSpec
    }
}

// MARK: - QueryResultChartDataState

enum QueryResultChartDataState: Equatable, Sendable {
    case ready(ChartData)
    case invalidConfiguration

    // MARK: Internal

    static func resolve(tableRows: TableRows, spec: ChartSpec) -> Self {
        guard let data = try? ChartDataBuilder.build(from: tableRows, spec: spec) else {
            return .invalidConfiguration
        }
        return .ready(data)
    }
}

// MARK: - QueryResultChartDataKey

struct QueryResultChartDataKey: Equatable, Sendable {
    // MARK: Lifecycle

    init(dataRevision: Int, spec: ChartSpec) {
        self.dataRevision = dataRevision
        self.xColumn = spec.xColumn
        self.yColumns = spec.yColumns
        self.seriesColumn = spec.seriesColumn
        self.sortOrder = spec.sortOrder
    }

    // MARK: Internal

    let dataRevision: Int
    let xColumn: ChartColumnID
    let yColumns: [ChartColumnID]
    let seriesColumn: ChartColumnID?
    let sortOrder: ChartSortOrder
}

// MARK: - ChartPointAccessibilityFormatter

enum ChartPointAccessibilityFormatter {
    // MARK: Internal

    static func label(for point: ChartPoint, xColumnName: String) -> String {
        let xCoordinate = String(
            format: String(localized: "%@: %@"),
            xColumnName,
            description(for: point.x)
        )
        return String(
            format: String(localized: "%@, %@"),
            point.seriesLabel,
            xCoordinate
        )
    }

    // MARK: Private

    private static func description(for value: ChartXValue) -> String {
        switch value {
        case let .category(value):
            value
        case let .number(value):
            value.formatted()
        case let .date(value):
            value.formatted(date: .abbreviated, time: .shortened)
        }
    }
}

// MARK: - ChartRenderSeries

struct ChartRenderSeries: Equatable {
    // MARK: Lifecycle

    init(point: ChartPoint) {
        self.groupingID = point.seriesID
        self.styleLabel = point.seriesLabel
    }

    // MARK: Internal

    let groupingID: String
    let styleLabel: String
}

// MARK: - QueryResultChartDataCache

private struct QueryResultChartDataCache: Equatable, Sendable {
    let key: QueryResultChartDataKey
    let state: QueryResultChartDataState
}

// MARK: - QueryResultChartView

struct QueryResultChartView: View {
    // MARK: Lifecycle

    init(
        tableRows: TableRows,
        spec: Binding<ChartSpec?>,
        dataRevision: Int = 0
    ) {
        self.tableRows = tableRows
        self.dataRevision = dataRevision
        self._spec = spec
    }

    // MARK: Internal

    @Binding var spec: ChartSpec?

    let tableRows: TableRows
    let dataRevision: Int

    var body: some View {
        VStack(spacing: 0) {
            switch QueryResultChartState.resolve(tableRows: tableRows, storedSpec: spec) {
            case .noRows:
                noRowsView
            case .needsConfiguration:
                needsConfigurationView
            case let .configured(resolvedSpec):
                let reconciliation = QueryResultChartReconciliation(
                    storedSpec: spec,
                    resolvedSpec: resolvedSpec
                )
                configuredChart(spec: resolvedSpec)
                    .onChange(of: reconciliation, initial: true) { _, current in
                        if let repairedSpec = current.specToPersist {
                            spec = repairedSpec
                        }
                    }
            }
        }
    }

    // MARK: Private

    @State private var cachedData: QueryResultChartDataCache?

    private var noRowsView: some View {
        ContentUnavailableView {
            Label(String(localized: "No rows to chart"), systemImage: "chart.xyaxis.line")
        } description: {
            Text(String(localized: "Run a query that returns rows, then switch back to Chart."))
        }
    }

    private var needsConfigurationView: some View {
        ContentUnavailableView {
            Label(String(localized: "Choose chart columns"), systemImage: "slider.horizontal.3")
        } description: {
            Text(String(localized: "Charts need an X-axis column and at least one numeric Y-axis column."))
        }
    }

    private var invalidConfigurationView: some View {
        ContentUnavailableView {
            Label(String(localized: "Unable to build chart"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(String(localized: "Choose a different X axis or at least one Y-axis column."))
        }
    }

    @ViewBuilder
    private func configuredChart(spec resolvedSpec: ChartSpec) -> some View {
        let resolvedSpecBinding = Binding(
            get: {
                QueryResultChartState.reconciledSpec(
                    tableRows: tableRows,
                    storedSpec: spec
                ) ?? resolvedSpec
            },
            set: { spec = $0 }
        )

        VStack(spacing: 0) {
            ChartConfigurationBar(tableRows: tableRows, spec: resolvedSpecBinding)
            Divider()

            chartDataContent(
                spec: resolvedSpec,
                key: QueryResultChartDataKey(dataRevision: dataRevision, spec: resolvedSpec)
            )
        }
    }

    private func chartDataContent(spec: ChartSpec, key: QueryResultChartDataKey) -> some View {
        Group {
            if let cachedData, cachedData.key == key {
                switch cachedData.state {
                case let .ready(data):
                    chartCanvas(data: data, spec: spec)
                case .invalidConfiguration:
                    invalidConfigurationView
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: key) {
            await rebuildChartData(spec: spec, key: key)
        }
    }

    private func chartCanvas(data: ChartData, spec: ChartSpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayTitle(for: spec))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)

            Chart(data.points) { point in
                mark(
                    for: point,
                    chartType: spec.chartType,
                    xColumnName: spec.xColumn.name
                )
            }
            .chartLegend(spec.showsLegend ? .visible : .hidden)
            .accessibilityLabel(displayTitle(for: spec))
            .accessibilityValue(
                String(
                    localized: "\(data.points.count) chart points",
                    comment: "Accessibility summary of the number of rendered chart points"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            chartStatus(data)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func chartStatus(_ data: ChartData) -> some View {
        if data.skippedValueCount > 0 || data.isSampled {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    chartStatusItems(data)
                }
                VStack(alignment: .leading, spacing: 4) {
                    chartStatusItems(data)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func chartStatusItems(_ data: ChartData) -> some View {
        if data.skippedValueCount > 0 {
            Label {
                Text("\(data.skippedValueCount) values skipped")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        if data.isSampled {
            Label {
                Text("Showing a \(data.points.count)-point sample")
            } icon: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
            }
        }
    }

    private func rebuildChartData(spec: ChartSpec, key: QueryResultChartDataKey) async {
        let tableRows = tableRows
        let state = await Task.detached(priority: .userInitiated) {
            QueryResultChartDataState.resolve(tableRows: tableRows, spec: spec)
        }.value
        guard !Task.isCancelled else {
            return
        }
        cachedData = QueryResultChartDataCache(key: key, state: state)
    }

    @ChartContentBuilder
    private func mark(
        for point: ChartPoint,
        chartType: ChartType,
        xColumnName: String
    )
        -> some ChartContent
    {
        switch point.x {
        case let .category(value):
            typedMark(for: point, x: value, chartType: chartType, xColumnName: xColumnName)
        case let .number(value):
            typedMark(for: point, x: value, chartType: chartType, xColumnName: xColumnName)
        case let .date(value):
            typedMark(for: point, x: value, chartType: chartType, xColumnName: xColumnName)
        }
    }

    @ChartContentBuilder
    private func typedMark<X: Plottable>(
        for point: ChartPoint,
        x: X,
        chartType: ChartType,
        xColumnName: String
    )
        -> some ChartContent
    {
        let renderSeries = ChartRenderSeries(point: point)
        switch chartType {
        case .line:
            LineMark(
                x: .value("X", x),
                y: .value("Y", point.y),
                series: .value("Series ID", renderSeries.groupingID)
            )
            .foregroundStyle(by: .value("Series", renderSeries.styleLabel))
            .accessibilityLabel(
                ChartPointAccessibilityFormatter.label(for: point, xColumnName: xColumnName)
            )
            .accessibilityValue(point.y.formatted())
        case .bar:
            BarMark(x: .value("X", x), y: .value("Y", point.y))
                .foregroundStyle(by: .value("Series", renderSeries.styleLabel))
                .accessibilityLabel(
                    ChartPointAccessibilityFormatter.label(for: point, xColumnName: xColumnName)
                )
                .accessibilityValue(point.y.formatted())
        case .area:
            AreaMark(
                x: .value("X", x),
                y: .value("Y", point.y),
                series: .value("Series ID", renderSeries.groupingID)
            )
            .foregroundStyle(by: .value("Series", renderSeries.styleLabel))
            .accessibilityLabel(
                ChartPointAccessibilityFormatter.label(for: point, xColumnName: xColumnName)
            )
            .accessibilityValue(point.y.formatted())
        case .scatter:
            PointMark(x: .value("X", x), y: .value("Y", point.y))
                .foregroundStyle(by: .value("Series", renderSeries.styleLabel))
                .accessibilityLabel(
                    ChartPointAccessibilityFormatter.label(for: point, xColumnName: xColumnName)
                )
                .accessibilityValue(point.y.formatted())
        }
    }

    private func displayTitle(for spec: ChartSpec) -> String {
        let title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else {
            return title
        }
        let measures = spec.yColumns.map(\.name).formatted()
        return String(
            localized: "\(measures) by \(spec.xColumn.name)",
            comment: "Default chart title listing Y-axis measures followed by the X-axis dimension"
        )
    }
}
