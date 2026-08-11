# Query Result Visualization Design

## Summary

Add native, deterministic charts to TablePro query results on macOS. Users continue to write SQL manually or use an existing AI provider such as Codex or Claude to draft SQL, review it in the editor, and execute it themselves. After execution, the same result set can be viewed as Data, Chart, or JSON and exported through TablePro's existing CSV/XLSX export system.

## Goals

- Add Chart as a built-in query-result view alongside Data and JSON.
- Render charts locally with Apple Swift Charts on macOS 14 or later.
- Infer a useful initial chart from result column names, metadata, and values.
- Let users override chart type, axes, series, sorting, and presentation without rerunning SQL.
- Preserve an independent chart configuration for each result set, including pinned results, for the current app session.
- Make the existing CSV and XLSX query-result export workflow visible from the result toolbar.
- Keep SQL execution under explicit user control.

## Non-goals

- Dashboards containing multiple queries or charts.
- Persisting chart definitions across app launches.
- AI-generated chart configuration.
- Sending query-result data to an AI provider.
- Pie charts, pivot tables, calculated fields, or arbitrary chart scripting.
- Replacing the existing CSV/XLSX export plugins.

## User Flow

1. The user writes SQL directly or asks an existing AI provider to draft SQL in TablePro's editor.
2. The user reviews and executes the query.
3. TablePro displays Data by default.
4. The result toolbar provides Data, Chart, JSON, and Export actions.
5. Selecting Chart infers an initial chart configuration and renders the active result set.
6. The user can change chart type, X axis, one or more Y axes, an optional series column, sorting, title, legend visibility, and axis formatting.
7. Selecting Export opens TablePro's existing export dialog, including CSV and XLSX formats.
8. Switching among result sets restores each result set's in-memory chart configuration.

## UI Design

### Result toolbar

For query and table results, extend the existing result-view picker with a Chart option. Keep Data selected after a query finishes. Place an Export button adjacent to the view picker; it calls the existing query-result export command and does not introduce a separate export path.

### Chart view

The chart fills the result pane. A compact toolbar above it contains:

- Chart type: Line, Bar, Area, or Scatter.
- X-axis column.
- One or more Y-axis columns.
- Optional series/group column.
- Sort order: source order, ascending X, or descending X.
- Title text.
- Legend visibility.

Controls that do not apply to the selected chart type are hidden. The first release uses native Swift Charts styling and system colors; custom palettes and detailed theme editing remain out of scope.

### Empty and warning states

- No rows: show "Run a query that returns rows to create a chart."
- No compatible columns: show "Choose an X axis and at least one numeric Y axis."
- Invalid values: render valid points and show a nonblocking count such as "3 values could not be plotted."
- More than 5,000 renderable points: show that the chart is displaying a representative sample while export still includes the complete result.

## Architecture

### ChartSpec

`ChartSpec` is a `Codable`, `Equatable`, and `Sendable` value describing presentation only. It contains:

- `chartType`: line, bar, area, or scatter.
- `xColumn`: one result-column identifier.
- `yColumns`: one or more result-column identifiers.
- `seriesColumn`: an optional result-column identifier.
- `sortOrder`: source, ascending X, or descending X.
- `title`: user-editable text.
- `showsLegend`: Boolean.

Column identifiers use the result column's ordinal position plus name so duplicate column names remain addressable. `ChartSpec` does not contain SQL or copied result rows.

### ChartSpecInferrer

`ChartSpecInferrer` receives result columns and a bounded sample of rows. It returns an optional initial specification using deterministic rules in this order:

1. Date/time column plus one or more numeric columns: line chart.
2. Text/category column plus one or more numeric columns: bar chart.
3. Two or more numeric columns: scatter chart using the first numeric column as X and the second as Y.
4. Otherwise, no inferred specification.

Metadata type names are the primary signal. Value sampling handles drivers that provide weak or empty type metadata. Inference never sends data to an AI provider.

### ChartDataBuilder

`ChartDataBuilder` converts the active result set and a valid `ChartSpec` into typed chart points. It:

- Parses numeric values with a locale-independent decimal parser.
- Parses ISO-8601 and common SQL date/time representations.
- Preserves source order unless the specification requests X sorting.
- Skips null or malformed X/Y values and returns a skipped-value count.
- Expands multiple Y columns into separate series when no explicit series column is selected.
- Produces stable series identifiers and display labels.

The builder is a pure transformation with no database, UI, or AI dependencies.

### Rendering

`QueryResultChartView` renders builder output with Swift Charts. Separate mark construction is used for line, bar, area, and scatter charts while axes, legend, title, warning state, and accessibility labels share common presentation code.

### State ownership

Each `ResultSet` owns an optional `ChartSpec`. This keeps chart settings aligned with pinned and active result tabs. The state is intentionally in-memory for the first release. When a rerun replaces an unpinned result, the new result receives no chart specification and inference runs the first time Chart opens.

If selected columns disappear, validation removes invalid Y/series selections and attempts inference against the new columns. If no valid specification remains, the chart displays its configuration empty state.

### Rendering limit

Charts render at most 5,000 points. When a result exceeds the limit, deterministic stride sampling preserves the first and last points and selects evenly spaced intermediate points. Sampling affects rendering only. The underlying result set and CSV/XLSX export data remain complete.

## Export Integration

TablePro already provides CSV and XLSX export plugins and a query-result export dialog. The new Export button dispatches the existing `exportQueryResults` action for the active result set. No duplicate serializer or file writer will be created. Existing CSV injection protection, formatting options, streaming behavior, and XLSX row-limit handling remain authoritative.

Exporting a chart image is outside the first release.

## AI Boundary

Codex, Claude, and other configured providers continue to assist with SQL authoring through TablePro's existing AI panel and editor actions. Generated SQL is inserted into the editor and requires user execution. The charting feature itself is provider-neutral and does not invoke AI, execute SQL, or transmit result rows.

## Error Handling

- Treat parsing failures as skipped values rather than fatal chart errors.
- Validate every selected column against the active result before building points.
- Disable Chart when the active result represents only an execution status and has no columns.
- Surface rendering and inference problems within the chart pane; do not replace query execution errors.
- Reuse the existing export dialog's error and progress handling.

## Testing Strategy

Follow test-driven development for every production change.

### Unit tests

- Inference for date-plus-numeric, category-plus-numeric, and numeric-plus-numeric results.
- No inference for incompatible or empty results.
- Numeric, date, null, and malformed-value parsing.
- Multiple Y columns and explicit series grouping.
- Source, ascending-X, and descending-X ordering.
- Deterministic 5,000-point sampling that preserves endpoints.
- Chart-spec validation after columns are removed or renamed.
- Independent chart state for pinned result sets.

### UI and integration tests

- Result view mode exposes Chart for row-returning results.
- Data remains the default after query execution.
- Switching Data to Chart renders the inferred configuration.
- Switching result tabs restores the correct chart specification.
- Export remains available from Data and Chart modes and dispatches the existing export action.

### Verification

- Run focused unit suites during each red-green-refactor cycle.
- Run the complete TablePro test scheme after integration.
- Build the unsigned Debug macOS app with the repository's documented `xcodebuild` command.
- Manually exercise line, bar, area, and scatter charts with nulls and more than 5,000 rows.

## Acceptance Criteria

- A successful row-returning query defaults to Data and offers Chart in the result picker.
- Opening Chart produces a useful inferred visualization when compatible columns exist.
- Users can configure the supported chart properties without rerunning SQL.
- Null and malformed values do not crash or block the chart.
- More than 5,000 points are sampled deterministically for display with a visible notice.
- Pinned result sets retain independent chart configurations for the app session.
- Export opens the existing dialog and offers CSV and XLSX for the active query result.
- No chart operation executes SQL or sends result data to an AI provider.
- Focused tests, the full test scheme, and an unsigned Debug build complete successfully.
