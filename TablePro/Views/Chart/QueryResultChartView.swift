import Charts
import SwiftUI

enum QueryResultChartState: Equatable {
    case noRows
    case needsConfiguration
    case configured(ChartSpec)

    static func resolve(tableRows: TableRows, storedSpec: ChartSpec?) -> Self {
        guard !tableRows.columns.isEmpty, tableRows.count > 0 else { return .noRows }
        if let storedSpec, let valid = storedSpec.validated(for: tableRows) {
            return .configured(valid)
        }
        if let inferred = ChartSpecInferrer.infer(from: tableRows) {
            return .configured(inferred)
        }
        return .needsConfiguration
    }
}

struct QueryResultChartView: View {
    let tableRows: TableRows
    @Binding var spec: ChartSpec?

    var body: some View {
        VStack(spacing: 0) {
            switch QueryResultChartState.resolve(tableRows: tableRows, storedSpec: spec) {
            case .noRows:
                noRowsView
            case .needsConfiguration:
                needsConfigurationView
            case .configured(let resolvedSpec):
                configuredChart(spec: resolvedSpec)
                    .task {
                        if spec != resolvedSpec {
                            spec = resolvedSpec
                        }
                    }
            }
        }
    }

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

    private func configuredChart(spec resolvedSpec: ChartSpec) -> some View {
        let data = try! ChartDataBuilder.build(from: tableRows, spec: resolvedSpec)
        let resolvedSpecBinding = Binding(
            get: { spec ?? resolvedSpec },
            set: { spec = $0 }
        )

        return VStack(spacing: 0) {
            ChartConfigurationBar(tableRows: tableRows, spec: resolvedSpecBinding)
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(displayTitle(for: resolvedSpec))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                Chart(data.points) { point in
                    mark(for: point, chartType: resolvedSpec.chartType)
                }
                .chartLegend(resolvedSpec.showsLegend ? .visible : .hidden)
                .accessibilityLabel(displayTitle(for: resolvedSpec))
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
    }

    @ChartContentBuilder
    private func mark(for point: ChartPoint, chartType: ChartType) -> some ChartContent {
        switch point.x {
        case .category(let value):
            typedMark(for: point, x: value, chartType: chartType)
        case .number(let value):
            typedMark(for: point, x: value, chartType: chartType)
        case .date(let value):
            typedMark(for: point, x: value, chartType: chartType)
        }
    }

    @ChartContentBuilder
    private func typedMark<X: Plottable>(
        for point: ChartPoint,
        x: X,
        chartType: ChartType
    ) -> some ChartContent {
        switch chartType {
        case .line:
            LineMark(x: .value("X", x), y: .value("Y", point.y))
                .foregroundStyle(by: .value("Series", point.series))
                .accessibilityLabel(point.series)
                .accessibilityValue(point.y.formatted())
        case .bar:
            BarMark(x: .value("X", x), y: .value("Y", point.y))
                .foregroundStyle(by: .value("Series", point.series))
                .accessibilityLabel(point.series)
                .accessibilityValue(point.y.formatted())
        case .area:
            AreaMark(x: .value("X", x), y: .value("Y", point.y))
                .foregroundStyle(by: .value("Series", point.series))
                .accessibilityLabel(point.series)
                .accessibilityValue(point.y.formatted())
        case .scatter:
            PointMark(x: .value("X", x), y: .value("Y", point.y))
                .foregroundStyle(by: .value("Series", point.series))
                .accessibilityLabel(point.series)
                .accessibilityValue(point.y.formatted())
        }
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

    private func displayTitle(for spec: ChartSpec) -> String {
        let title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return title }
        let measures = spec.yColumns.map(\.name).formatted()
        return String(
            localized: "\(measures) by \(spec.xColumn.name)",
            comment: "Default chart title listing Y-axis measures followed by the X-axis dimension"
        )
    }
}
