import SwiftUI

// MARK: - PaginationCallbacks

struct PaginationCallbacks {
    let onFirst: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onLast: () -> Void
    let onPageSizeChange: (Int) -> Void
    let onShowAll: () -> Void
    let onGoToPage: (Int) -> Void
    let onRequestExactCount: () -> Void
}

// MARK: - StatusBarColumnState

struct StatusBarColumnState {
    let hidden: Set<String>
    let all: [String]
    let onToggle: (String) -> Void
    let onShowAll: () -> Void
    let onHideAll: ([String]) -> Void
    let onReset: () -> Void
}

// MARK: - StatusBarStructureState

struct StatusBarStructureState {
    let footer: StructureFooterState
    let onAdd: () -> Void
    let onRemove: () -> Void
}

// MARK: - MainStatusBarPolicy

enum MainStatusBarPolicy {
    static func showsRowStatus(viewMode: ResultsViewMode) -> Bool {
        viewMode == .data || viewMode == .json
    }

    static func showsGridControls(viewMode: ResultsViewMode) -> Bool {
        viewMode == .data || viewMode == .json
    }

    static func showsExport(viewMode: ResultsViewMode, hasColumns: Bool) -> Bool {
        hasColumns && (viewMode == .data || viewMode == .chart)
    }

    static func showsAddRow(viewMode: ResultsViewMode, canAddRow: Bool) -> Bool {
        viewMode == .data && canAddRow
    }
}

// MARK: - MainStatusBarView

struct MainStatusBarView: View {
    // MARK: Internal

    let snapshot: StatusBarSnapshot
    let filterState: TabFilterState
    let selectedRowIndices: Set<Int>
    @Binding var viewMode: ResultsViewMode

    let paginationCallbacks: PaginationCallbacks
    let columnState: StatusBarColumnState
    let structureState: StatusBarStructureState
    let onToggleFilters: () -> Void
    let onFetchAll: (() -> Void)?
    let onAddRow: (() -> Void)?
    let onExport: (() -> Void)?

    var body: some View {
        HStack {
            if snapshot.tabId != nil {
                if snapshot.tabType == .table, snapshot.hasTableName {
                    Picker(String(localized: "View Mode"), selection: $viewMode) {
                        Label("Data", systemImage: "tablecells").tag(ResultsViewMode.data)
                        Label("Chart", systemImage: "chart.xyaxis.line").tag(ResultsViewMode.chart)
                        Label("Structure", systemImage: "list.bullet.rectangle").tag(ResultsViewMode.structure)
                        Label("JSON", systemImage: "curlybraces").tag(ResultsViewMode.json)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                    .controlSize(.small)
                } else if snapshot.hasColumns {
                    Picker(String(localized: "View Mode"), selection: $viewMode) {
                        Label("Data", systemImage: "tablecells").tag(ResultsViewMode.data)
                        Label("Chart", systemImage: "chart.xyaxis.line").tag(ResultsViewMode.chart)
                        Label("JSON", systemImage: "curlybraces").tag(ResultsViewMode.json)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .controlSize(.small)
                }
            }

            Spacer()

            if MainStatusBarPolicy.showsRowStatus(viewMode: viewMode), snapshot.hasRows {
                HStack(spacing: 4) {
                    if snapshot.pagination.isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Loading more rows"))
                    } else {
                        Text(snapshot.rowInfoText(selectedCount: selectedRowIndices.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if snapshot.tabType == .table, !snapshot.pagination.isLoadingMore,
                       snapshot.pagination.isApproximateRowCount || snapshot.pagination.totalRowCount == nil
                    {
                        if snapshot.pagination.isCountingExact {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(String(localized: "Counting rows"))
                        } else {
                            Button {
                                paginationCallbacks.onRequestExactCount()
                            } label: {
                                Text("Count exactly")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                            .help(String(localized: "Replace the estimate with an exact row count."))
                        }
                    }

                    if snapshot.tabType == .query, snapshot.pagination.hasMoreRows, !snapshot.pagination.isLoadingMore {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                        Text("truncated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            onFetchAll?()
                        } label: {
                            Text("Fetch All")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }

                    if let statusMessage = snapshot.statusMessage {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isStructureMode, structureState.footer.isActive {
                    structureFooterControls(state: structureState.footer)
                }

                if MainStatusBarPolicy.showsExport(viewMode: viewMode, hasColumns: snapshot.hasColumns), let onExport {
                    Button {
                        onExport()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                    }
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Export Query Results"))
                }

                if MainStatusBarPolicy.showsAddRow(viewMode: viewMode, canAddRow: onAddRow != nil), let onAddRow {
                    Button {
                        onAddRow()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                    }
                    .controlSize(.small)
                    .help(addRowHelp)
                    .accessibilityLabel(String(localized: "Add Row"))
                }

                if MainStatusBarPolicy.showsGridControls(viewMode: viewMode) {
                    if snapshot.hasColumns {
                        Button {
                            showColumnPopover.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: !columnState.hidden.isEmpty
                                    ? "eye.slash.circle.fill"
                                    : "eye.circle")
                                Text("Columns")
                                if !columnState.hidden.isEmpty {
                                    let visible = columnState.all.count - columnState.hidden.count
                                    Text("(\(visible)/\(columnState.all.count))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .controlSize(.small)
                        .accessibilityLabel(columnsAccessibilityLabel)
                        .popover(isPresented: $showColumnPopover, arrowEdge: .top) {
                            ColumnVisibilityPopover(
                                columns: columnState.all,
                                hiddenColumns: columnState.hidden,
                                onToggleColumn: columnState.onToggle,
                                onShowAll: columnState.onShowAll,
                                onHideAll: columnState.onHideAll,
                                onReset: columnState.onReset
                            )
                        }
                    }

                    if snapshot.tabType == .table, snapshot.hasTableName {
                        Toggle(isOn: Binding(
                            get: { filterState.isVisible },
                            set: { _ in onToggleFilters() }
                        )) {
                            HStack(spacing: 4) {
                                Image(systemName: filterState.hasAppliedFilters
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease.circle")
                                Text("Filters")
                                if filterState.hasAppliedFilters {
                                    Text("(\(filterState.appliedFilters.count))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .help(filterToggleHelp)
                        .accessibilityLabel(String(localized: "Filters"))
                        .accessibilityAddTraits(filterState.isVisible ? .isSelected : [])
                    }

                    if snapshot.tabType == .table, snapshot.hasTableName, snapshot.showsPaginationControls {
                        PaginationControlsView(
                            pagination: snapshot.pagination,
                            loadedRowCount: snapshot.rowCount,
                            onFirst: paginationCallbacks.onFirst,
                            onPrevious: paginationCallbacks.onPrevious,
                            onNext: paginationCallbacks.onNext,
                            onLast: paginationCallbacks.onLast,
                            onPageSizeChange: paginationCallbacks.onPageSizeChange,
                            onShowAll: paginationCallbacks.onShowAll,
                            onGoToPage: paginationCallbacks.onGoToPage
                        )
                    }
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: snapshot.tabId) { _, _ in
            showColumnPopover = false
        }
    }

    // MARK: Private

    @State private var showColumnPopover = false

    private var isStructureMode: Bool {
        viewMode == .structure
    }

    private var filterToggleHelp: String {
        helpText(String(localized: "Toggle Filters"), shortcut: .toggleFilters)
    }

    private var addRowHelp: String {
        helpText(String(localized: "Add Row"), shortcut: .addRow)
    }

    private var columnsAccessibilityLabel: String {
        guard !columnState.hidden.isEmpty else {
            return String(localized: "Columns")
        }
        let visible = columnState.all.count - columnState.hidden.count
        return String(format: String(localized: "%d of %d columns visible"), visible, columnState.all.count)
    }

    private func structureFooterControls(state: StructureFooterState) -> some View {
        AddRemoveControlGroup(
            addLabel: state.addLabel,
            removeLabel: state.removeLabel,
            canAdd: state.canAdd,
            canRemove: state.canRemove,
            onAdd: { structureState.onAdd() },
            onRemove: { structureState.onRemove() }
        )
    }

    private func helpText(_ label: String, shortcut action: ShortcutAction) -> String {
        AppSettingsManager.shared.keyboard.shortcutHint(label, for: action)
    }
}
