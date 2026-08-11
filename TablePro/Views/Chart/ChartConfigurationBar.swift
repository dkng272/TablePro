import SwiftUI

struct ChartConfigurationBar: View {
    let tableRows: TableRows
    @Binding var spec: ChartSpec

    private var columns: [ChartColumnID] {
        tableRows.columns.enumerated().map {
            ChartColumnID(ordinal: $0.offset, name: $0.element)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Picker(String(localized: "Chart Type"), selection: $spec.chartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Text(type.localizedName).tag(type)
                    }
                }

                Picker(String(localized: "X Axis"), selection: $spec.xColumn) {
                    ForEach(columns) { column in
                        Text(column.name).tag(column)
                    }
                }

                yColumnMenu
                seriesPicker

                TextField(String(localized: "Chart title"), text: $spec.title)
                    .frame(minWidth: 140, idealWidth: 190, maxWidth: 240)
                    .accessibilityLabel(String(localized: "Chart title"))

                Toggle(String(localized: "Legend"), isOn: $spec.showsLegend)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .controlSize(.small)
        .background(.bar)
    }

    private var yColumnMenu: some View {
        Menu {
            ForEach(columns) { column in
                Toggle(column.name, isOn: yColumnBinding(for: column))
                    .disabled(column == spec.xColumn && !spec.yColumns.contains(column))
            }
        } label: {
            Label(yColumnSummary, systemImage: "chart.bar.xaxis")
        }
        .accessibilityLabel(String(localized: "Y Axis"))
        .help(String(localized: "Choose one or more Y-axis columns"))
    }

    private var seriesPicker: some View {
        Picker(String(localized: "Series"), selection: $spec.seriesColumn) {
            Text(String(localized: "None")).tag(nil as ChartColumnID?)
            ForEach(columns) { column in
                Text(column.name).tag(Optional(column))
            }
        }
    }

    private var yColumnSummary: String {
        if spec.yColumns.count == 1, let column = spec.yColumns.first {
            return column.name
        }
        return String(
            localized: "Y Axis (\(spec.yColumns.count))",
            comment: "Chart configuration summary showing the number of selected Y-axis columns"
        )
    }

    private func yColumnBinding(for column: ChartColumnID) -> Binding<Bool> {
        Binding(
            get: { spec.yColumns.contains(column) },
            set: { isSelected in
                if isSelected {
                    spec.yColumns = columns.filter {
                        spec.yColumns.contains($0) || $0 == column
                    }
                } else {
                    spec.yColumns.removeAll { $0 == column }
                }
            }
        )
    }
}
