# Query Result Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic native charts and a visible CSV/XLSX export action to macOS query results while preserving Data as the default view and leaving AI responsible only for drafting SQL.

**Architecture:** Pure chart-domain types infer and validate a `ChartSpec`, then transform `TableRows` into bounded typed `ChartData`. A Swift Charts view renders that data and binds controls to the active `ResultSet.chartSpec`; `MainEditorContentView` adds the Chart result mode, while `MainStatusBarView` exposes Chart and dispatches the existing export command.

**Tech Stack:** Swift 6, SwiftUI, Apple Swift Charts, Observation, Swift Testing, XcodeGen, XCTest/Xcode build tooling.

## Global Constraints

- Support macOS 14 or later.
- Use Apple Swift Charts; add no third-party chart dependency.
- Keep Data as the default result view after execution.
- Support line, bar, area, and scatter charts only.
- Render at most 5,000 chart points using deterministic endpoint-preserving sampling.
- Preserve all result rows for CSV/XLSX export.
- Store chart configuration per `ResultSet` for the current app session only.
- Never execute SQL or send result rows to an AI provider from chart code.
- Reuse the existing query-result export dialog and CSV/XLSX plugins.
- Use `String(localized:)` for user-facing text, four-space indentation, and no force unwraps or force casts.

---

## File Map

- `TablePro/Models/Chart/ChartSpec.swift`: chart configuration, column identity, enums, and validation.
- `TablePro/Models/Chart/ChartSpecInferrer.swift`: deterministic initial chart inference.
- `TablePro/Models/Chart/ChartData.swift`: renderer-neutral chart point and build-result types.
- `TablePro/Models/Chart/ChartDataBuilder.swift`: parsing, grouping, sorting, skipped-value accounting, and sampling.
- `TablePro/Views/Chart/QueryResultChartView.swift`: Swift Charts rendering and empty/warning states.
- `TablePro/Views/Chart/ChartConfigurationBar.swift`: chart type, axes, series, title, and legend controls.
- `TablePro/Models/Query/ResultSet.swift`: in-memory `chartSpec` ownership.
- `TablePro/Models/Query/QueryTab.swift`: add `.chart` result mode.
- `TablePro/Views/Main/Child/MainEditorContentView.swift`: route the active result into the chart view and bind its specification.
- `TablePro/Views/Main/Child/MainStatusBarView.swift`: expose Chart and the existing Export action.
- `TableProTests/Models/Chart/ChartSpecInferrerTests.swift`: inference behavior.
- `TableProTests/Models/Chart/ChartDataBuilderTests.swift`: parsing, grouping, sorting, and sampling behavior.
- `TableProTests/Models/Chart/ChartSpecValidationTests.swift`: specification repair and invalidation.
- `TableProTests/Views/Chart/QueryResultChartViewTests.swift`: view construction and empty-state selection.
- `TableProTests/Views/Main/ResultPinningTests.swift`: per-result chart state.
- `TableProTests/Views/Main/ResultTabBarPolicyTests.swift`: Chart preserves result tabs and pinning.
- `TableProTests/Views/Main/MainStatusBarLayoutTests.swift`: Chart mode and Export visibility policy.

---

### Task 1: Chart specification and deterministic inference

**Files:**
- Create: `TablePro/Models/Chart/ChartSpec.swift`
- Create: `TablePro/Models/Chart/ChartSpecInferrer.swift`
- Create: `TableProTests/Models/Chart/ChartSpecInferrerTests.swift`
- Create: `TableProTests/Models/Chart/ChartSpecValidationTests.swift`

**Interfaces:**
- Produces: `ChartColumnID`, `ChartType`, `ChartSortOrder`, and `ChartSpec`.
- Produces: `ChartSpec.validated(for:) -> ChartSpec?`.
- Produces: `ChartSpecInferrer.infer(from:) -> ChartSpec?`.
- Consumes: existing `TableRows`, `ColumnType`, and `PluginCellValue`.

- [ ] **Step 1: Write failing inference tests**

Create test fixtures with explicit column metadata and verify the priority rules:

```swift
import TableProPluginKit
import Testing
@testable import TablePro

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
}
```

- [ ] **Step 2: Write failing validation tests**

```swift
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
```

- [ ] **Step 3: Generate the project and run the focused tests to verify RED**

Run:

```bash
scripts/generate-project.sh
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation \
  -only-testing:TableProTests/ChartSpecInferrerTests \
  -only-testing:TableProTests/ChartSpecValidationTests
```

Expected: compilation fails because `ChartSpec`, `ChartColumnID`, and `ChartSpecInferrer` do not exist.

- [ ] **Step 4: Implement the chart specification**

Use these public-to-the-app declarations in `ChartSpec.swift`:

```swift
import Foundation

struct ChartColumnID: Codable, Equatable, Hashable, Sendable, Identifiable {
    let ordinal: Int
    let name: String
    var id: String { "\(ordinal):\(name)" }
}

enum ChartType: String, Codable, CaseIterable, Sendable {
    case line
    case bar
    case area
    case scatter

    var localizedName: String {
        switch self {
        case .line: String(localized: "Line")
        case .bar: String(localized: "Bar")
        case .area: String(localized: "Area")
        case .scatter: String(localized: "Scatter")
        }
    }
}

enum ChartSortOrder: String, Codable, CaseIterable, Sendable {
    case source
    case ascendingX
    case descendingX
}

struct ChartSpec: Codable, Equatable, Sendable {
    var chartType: ChartType
    var xColumn: ChartColumnID
    var yColumns: [ChartColumnID]
    var seriesColumn: ChartColumnID?
    var sortOrder: ChartSortOrder = .source
    var title: String = ""
    var showsLegend: Bool = true

    func validated(for tableRows: TableRows) -> ChartSpec? {
        let available = Set(tableRows.columns.enumerated().map {
            ChartColumnID(ordinal: $0.offset, name: $0.element)
        })
        guard available.contains(xColumn) else { return nil }
        var copy = self
        copy.yColumns = yColumns.filter(available.contains)
        guard !copy.yColumns.isEmpty else { return nil }
        if let seriesColumn, !available.contains(seriesColumn) {
            copy.seriesColumn = nil
        }
        return copy
    }
}
```

- [ ] **Step 5: Implement inference**

Implement `ChartSpecInferrer` with metadata-first classification and a 50-row fallback sample. Numeric metadata is `.integer` or `.decimal`; temporal metadata is `.date`, `.timestamp`, or `.datetime`; text/category metadata is `.text` or `.enumType`. Only use sampled values when the metadata array is shorter than the columns array. Return Y columns in source-column order and exclude X from Y.

```swift
enum ChartSpecInferrer {
    static func infer(from tableRows: TableRows) -> ChartSpec? {
        let columns = tableRows.columns.enumerated().map {
            ChartColumnID(ordinal: $0.offset, name: $0.element)
        }
        let kinds = columns.map { kind(at: $0.ordinal, in: tableRows) }
        let numeric = columns.filter { kinds[$0.ordinal] == .numeric }

        if let date = columns.first(where: { kinds[$0.ordinal] == .temporal }), !numeric.isEmpty {
            return ChartSpec(chartType: .line, xColumn: date, yColumns: numeric)
        }
        if let category = columns.first(where: { kinds[$0.ordinal] == .category }), !numeric.isEmpty {
            return ChartSpec(chartType: .bar, xColumn: category, yColumns: numeric)
        }
        if numeric.count >= 2 {
            return ChartSpec(chartType: .scatter, xColumn: numeric[0], yColumns: [numeric[1]])
        }
        return nil
    }
}
```

- [ ] **Step 6: Run the focused tests to verify GREEN**

Run the command from Step 3. Expected: both suites pass with zero failures.

- [ ] **Step 7: Commit the domain and inference layer**

```bash
git add TablePro/Models/Chart TableProTests/Models/Chart
git commit -m "feat: infer chart specifications from query results"
```

---

### Task 2: Typed chart-data builder and 5,000-point sampling

**Files:**
- Create: `TablePro/Models/Chart/ChartData.swift`
- Create: `TablePro/Models/Chart/ChartDataBuilder.swift`
- Create: `TableProTests/Models/Chart/ChartDataBuilderTests.swift`

**Interfaces:**
- Consumes: `ChartSpec` and `TableRows` from Task 1.
- Produces: `ChartXValue`, `ChartPoint`, `ChartData`, and `ChartDataBuilder.build(from:spec:limit:)`.

- [ ] **Step 1: Write failing parsing and grouping tests**

```swift
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
```

- [ ] **Step 2: Write failing sorting, grouping, date, and sampling tests**

Add the following tests alongside the parsing tests:

```swift
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
```

The sampling test uses a 5,001-point input, requires exactly 5,000 output points, preserves the original first and last X values, and requires identical point IDs across repeated builds.

```swift
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
```

- [ ] **Step 3: Run the builder suite to verify RED**

```bash
scripts/generate-project.sh
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation \
  -only-testing:TableProTests/ChartDataBuilderTests
```

Expected: compilation fails because the chart-data types do not exist.

- [ ] **Step 4: Implement renderer-neutral chart data**

```swift
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
```

- [ ] **Step 5: Implement build, parse, sort, and sample**

Use `PluginCellValue.asText`, `Double`, `ISO8601DateFormatter`, and fixed `en_US_POSIX` date formats `yyyy-MM-dd`, `yyyy-MM-dd HH:mm:ss`, and `yyyy-MM-dd'T'HH:mm:ss`. Build points with IDs `"row:<row>:y:<ordinal>:series:<label>"`. Sort only after parsing. Sample the finished point array with indices `round(Double(i) * Double(count - 1) / Double(limit - 1))` for `i` in `0..<limit`; this preserves endpoints and is deterministic.

```swift
enum ChartDataBuilder {
    static let defaultPointLimit = 5_000

    static func build(
        from tableRows: TableRows,
        spec: ChartSpec,
        limit: Int = defaultPointLimit
    ) throws -> ChartData {
        guard let validSpec = spec.validated(for: tableRows) else {
            throw ChartDataBuilderError.invalidSpecification
        }
        let built = buildAllPoints(from: tableRows, spec: validSpec)
        let sorted = sort(built.points, order: validSpec.sortOrder)
        let sampled = sample(sorted, limit: limit)
        return ChartData(
            points: sampled,
            skippedValueCount: built.skipped,
            isSampled: sampled.count < sorted.count
        )
    }
}
```

- [ ] **Step 6: Run the builder suite to verify GREEN**

Run the command from Step 3. Expected: the suite passes with zero failures.

- [ ] **Step 7: Commit the chart-data layer**

```bash
git add TablePro/Models/Chart TableProTests/Models/Chart
git commit -m "feat: build typed chart data from result rows"
```

---

### Task 3: Per-result chart state and Chart result mode

**Files:**
- Modify: `TablePro/Models/Query/ResultSet.swift`
- Modify: `TablePro/Models/Query/QueryTab.swift`
- Modify: `TableProTests/Views/Main/ResultPinningTests.swift`
- Modify: `TableProTests/Views/Main/ResultTabBarPolicyTests.swift`

**Interfaces:**
- Consumes: `ChartSpec` from Task 1.
- Produces: `ResultSet.chartSpec: ChartSpec?`.
- Produces: `ResultsViewMode.chart`.

- [ ] **Step 1: Write failing state tests**

Add a test proving two pinned results retain independent specifications and that replacing an unpinned result starts with `chartSpec == nil`:

```swift
@Test("Pinned results retain independent chart specifications")
@MainActor
func pinnedResultsRetainIndependentChartSpecs() {
    let first = Self.makeResultSet(label: "first", isPinned: true)
    let second = Self.makeResultSet(label: "second", isPinned: true)
    first.chartSpec = ChartSpec(
        chartType: .line,
        xColumn: .init(ordinal: 0, name: "x"),
        yColumns: [.init(ordinal: 1, name: "y")]
    )
    second.chartSpec = ChartSpec(
        chartType: .bar,
        xColumn: .init(ordinal: 0, name: "x"),
        yColumns: [.init(ordinal: 2, name: "z")]
    )

    #expect(first.chartSpec?.chartType == .line)
    #expect(second.chartSpec?.chartType == .bar)
}
```

Extend `pinningNeverOutrunsTheStrip` to iterate `[.data, .chart, .structure, .json]`, and add a focused assertion that Chart keeps the query result strip visible and pinnable.

- [ ] **Step 2: Run focused state tests to verify RED**

```bash
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation \
  -only-testing:TableProTests/ResultPinningTests \
  -only-testing:TableProTests/ResultTabBarPolicyTests
```

Expected: compilation fails because `.chart` and `ResultSet.chartSpec` do not exist.

- [ ] **Step 3: Add the minimal state**

Add `case chart` to `ResultsViewMode` and add this property beside the other result-specific display state:

```swift
var chartSpec: ChartSpec?
```

Do not add chart state to persisted tab models. Existing `ResultSet` replacement semantics automatically give new unpinned results a nil specification.

- [ ] **Step 4: Run focused state tests to verify GREEN**

Run the command from Step 2. Expected: both suites pass with zero failures.

- [ ] **Step 5: Commit result state**

```bash
git add TablePro/Models/Query TableProTests/Views/Main
git commit -m "feat: retain chart settings per result set"
```

---

### Task 4: Native Swift Charts view and configuration controls

**Files:**
- Create: `TablePro/Views/Chart/ChartConfigurationBar.swift`
- Create: `TablePro/Views/Chart/QueryResultChartView.swift`
- Create: `TableProTests/Views/Chart/QueryResultChartViewTests.swift`

**Interfaces:**
- Consumes: `TableRows`, `Binding<ChartSpec?>`, `ChartSpecInferrer`, and `ChartDataBuilder`.
- Produces: `QueryResultChartView(tableRows:spec:)`.
- Produces: `QueryResultChartState.resolve(tableRows:storedSpec:)` for testable empty/configured state selection.

- [ ] **Step 1: Write failing view-state tests**

```swift
import SwiftUI
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
```

- [ ] **Step 2: Generate the project and run the view suite to verify RED**

```bash
scripts/generate-project.sh
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation \
  -only-testing:TableProTests/QueryResultChartViewTests
```

Expected: compilation fails because the chart view and state resolver do not exist.

- [ ] **Step 3: Implement testable state resolution**

```swift
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
```

- [ ] **Step 4: Implement `ChartConfigurationBar`**

Build menus and controls from `tableRows.columns.enumerated()` using `ChartColumnID`. Use `Picker` for type/X/series, a `Menu` of toggles for multiple Y columns, `TextField` for title, and `Toggle` for legend visibility. Disable selecting the X column as a Y column. Every control writes directly through `Binding<ChartSpec>`.

```swift
struct ChartConfigurationBar: View {
    let tableRows: TableRows
    @Binding var spec: ChartSpec

    private var columns: [ChartColumnID] {
        tableRows.columns.enumerated().map { ChartColumnID(ordinal: $0.offset, name: $0.element) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker(String(localized: "Chart Type"), selection: $spec.chartType) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            Picker(String(localized: "X Axis"), selection: $spec.xColumn) {
                ForEach(columns) { Text($0.name).tag($0) }
            }
            yColumnMenu
            seriesPicker
            TextField(String(localized: "Chart title"), text: $spec.title)
            Toggle(String(localized: "Legend"), isOn: $spec.showsLegend)
        }
        .controlSize(.small)
        .padding(8)
    }
}
```

- [ ] **Step 5: Implement Swift Charts rendering**

Import `Charts`. Resolve/infer the spec on appearance, persist the inferred spec through the binding, build `ChartData`, and render one mark per point. Branch by `ChartXValue` so the X value passed to Swift Charts remains strongly typed. Use `LineMark`, `BarMark`, `AreaMark`, or `PointMark` according to `spec.chartType`; apply `.foregroundStyle(by: .value("Series", point.series))`. Add localized no-row/configuration states, skipped-value text, sampled-data text, title, legend visibility, and accessibility labels.

```swift
struct QueryResultChartView: View {
    let tableRows: TableRows
    @Binding var spec: ChartSpec?

    var body: some View {
        VStack(spacing: 0) {
            switch QueryResultChartState.resolve(tableRows: tableRows, storedSpec: spec) {
            case .noRows:
                ContentUnavailableView(
                    String(localized: "No rows to chart"),
                    systemImage: "chart.xyaxis.line"
                )
            case .needsConfiguration:
                ContentUnavailableView(
                    String(localized: "Choose chart columns"),
                    systemImage: "slider.horizontal.3"
                )
            case .configured(let resolvedSpec):
                configuredChart(spec: resolvedSpec)
                    .task { if spec != resolvedSpec { spec = resolvedSpec } }
            }
        }
    }
}
```

- [ ] **Step 6: Run the view suite to verify GREEN**

Run the command from Step 2. Expected: the suite passes with zero failures.

- [ ] **Step 7: Commit the chart UI**

```bash
git add TablePro/Views/Chart TableProTests/Views/Chart
git commit -m "feat: render query results with Swift Charts"
```

---

### Task 5: Integrate Chart and visible CSV/XLSX Export into query results

**Files:**
- Modify: `TablePro/Views/Main/Child/MainEditorContentView.swift`
- Modify: `TablePro/Views/Main/Child/MainStatusBarView.swift`
- Modify: `TableProTests/Views/Main/MainStatusBarLayoutTests.swift`
- Modify: `TableProTests/Views/Main/ResultTabBarPolicyTests.swift`

**Interfaces:**
- Consumes: `QueryResultChartView` from Task 4.
- Consumes: existing `MainContentCommandActions.exportQueryResults()`.
- Produces: `MainEditorContentView.chartSpecBinding(for:)`.
- Produces: `MainStatusBarView.onExport: (() -> Void)?` and `showsExport` policy.

- [ ] **Step 1: Write failing status-bar policy tests**

Update the status-bar construction test to pass `onExport: nil`, then add:

```swift
@Test("Export is available for row results in Data and Chart modes")
func exportVisibility() {
    #expect(MainStatusBarView.showsExport(viewMode: .data, hasColumns: true))
    #expect(MainStatusBarView.showsExport(viewMode: .chart, hasColumns: true))
    #expect(!MainStatusBarView.showsExport(viewMode: .structure, hasColumns: true))
    #expect(!MainStatusBarView.showsExport(viewMode: .data, hasColumns: false))
}

@Test("Add Row remains hidden in Chart mode")
func addRowHiddenInChartMode() {
    #expect(!MainStatusBarView.showsAddRow(viewMode: .chart, canAddRow: true))
}
```

- [ ] **Step 2: Run focused integration tests to verify RED**

```bash
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation \
  -only-testing:TableProTests/MainStatusBarLayoutTests \
  -only-testing:TableProTests/ResultTabBarPolicyTests
```

Expected: compilation fails because `showsExport` and the new initializer argument do not exist.

- [ ] **Step 3: Add Chart to the result picker and Export to the status bar**

Add `let onExport: (() -> Void)?` to `MainStatusBarView`, add this policy, and render a small Export button in the right-side controls:

```swift
static func showsExport(viewMode: ResultsViewMode, hasColumns: Bool) -> Bool {
    hasColumns && (viewMode == .data || viewMode == .chart)
}
```

For query results, expand the segmented picker to Data, Chart, and JSON. For table results, use Data, Chart, Structure, and JSON. Increase the picker width so labels do not truncate. The Export button uses `square.and.arrow.up`, calls `onExport`, and has the localized accessibility label "Export Query Results".

- [ ] **Step 4: Route `.chart` through `MainEditorContentView`**

Add a `.chart` switch case after `.json`. Keep the result tab bar visible, resolve the active rows, and create a binding to the active `ResultSet.chartSpec`:

```swift
case .chart:
    resultTabBarSection(tab: tab)
    QueryResultChartView(
        tableRows: resolvedTableRows(for: tab),
        spec: chartSpecBinding(for: tab)
    )
    .id(tab.display.activeResultSetId)
```

Implement the binding by mutating the observable active result object on the main actor:

```swift
private func chartSpecBinding(for tab: QueryTab) -> Binding<ChartSpec?> {
    Binding(
        get: { tab.display.activeResultSet?.chartSpec },
        set: { tab.display.activeResultSet?.chartSpec = $0 }
    )
}
```

Pass `onExport: { coordinator.commandActions?.exportQueryResults() }` into `MainStatusBarView`. Do not create a new exporter.

- [ ] **Step 5: Run focused integration tests to verify GREEN**

Run the command from Step 2. Expected: both suites pass with zero failures.

- [ ] **Step 6: Run all chart and result tests**

```bash
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation \
  -only-testing:TableProTests/ChartSpecInferrerTests \
  -only-testing:TableProTests/ChartSpecValidationTests \
  -only-testing:TableProTests/ChartDataBuilderTests \
  -only-testing:TableProTests/QueryResultChartViewTests \
  -only-testing:TableProTests/ResultPinningTests \
  -only-testing:TableProTests/ResultTabBarPolicyTests \
  -only-testing:TableProTests/MainStatusBarLayoutTests
```

Expected: all selected suites pass with zero failures.

- [ ] **Step 7: Commit result integration**

```bash
git add TablePro/Views/Main TableProTests/Views/Main
git commit -m "feat: add chart and export actions to query results"
```

---

### Task 6: Full verification and manual acceptance pass

**Files:**
- Modify only files required to fix failures exposed by verification.

**Interfaces:**
- Consumes: the complete feature from Tasks 1–5.
- Produces: fresh test and build evidence for the acceptance criteria.

- [ ] **Step 1: Regenerate projects and verify formatting**

```bash
scripts/generate-project.sh
swiftformat --lint TablePro/Models/Chart TablePro/Views/Chart \
  TablePro/Models/Query/ResultSet.swift TablePro/Models/Query/QueryTab.swift \
  TablePro/Views/Main/Child/MainEditorContentView.swift \
  TablePro/Views/Main/Child/MainStatusBarView.swift \
  TableProTests/Models/Chart TableProTests/Views/Chart
git diff --check
```

Expected: format lint and whitespace checks exit successfully.

- [ ] **Step 2: Run the complete macOS test scheme**

```bash
xcodebuild -project TablePro.xcodeproj -scheme TablePro test \
  -skipPackagePluginValidation
```

Expected: `** TEST SUCCEEDED **` with zero failed tests.

- [ ] **Step 3: Build the unsigned Debug app**

```bash
xcodebuild \
  -project TablePro.xcodeproj \
  -scheme TablePro \
  -configuration Debug \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Exercise the acceptance scenarios manually**

Launch the Debug app and run local queries that return:

```sql
SELECT '2026-01-01' AS month, 10 AS revenue
UNION ALL SELECT '2026-02-01', 12;

SELECT 'North' AS region, 10 AS revenue
UNION ALL SELECT 'South', 12;

SELECT 1 AS price, 10 AS volume
UNION ALL SELECT 2, 12;
```

Verify Data remains the default; Chart infers line, bar, and scatter configurations; chart controls update without rerunning SQL; pinned results keep independent settings; malformed/null values show a warning; and Export opens the existing dialog with CSV and XLSX.

- [ ] **Step 5: Review the final diff against the specification**

```bash
git status --short
git diff upstream/main...HEAD --stat
git diff upstream/main...HEAD --check
```

Confirm every acceptance criterion in `docs/superpowers/specs/2026-08-11-query-result-visualization-design.md` has code or test coverage and that no AI transport, SQL execution, CSV writer, or XLSX writer was modified.

- [ ] **Step 6: Commit verification fixes if Step 1–5 required changes**

```bash
git add TablePro TableProTests
git commit -m "fix: complete query result chart verification"
```

Skip this commit when verification required no code changes.
