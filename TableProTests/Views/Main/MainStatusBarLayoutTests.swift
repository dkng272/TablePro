//
//  MainStatusBarLayoutTests.swift
//  TableProTests
//

import Foundation
import SwiftUI
import TableProPluginKit
import Testing

@testable import TablePro

@Suite("MainStatusBarView Layout")
@MainActor
struct MainStatusBarLayoutTests {
    @Test("Status bar can be instantiated with empty snapshot")
    func instantiateWithEmptySnapshot() {
        let view = MainStatusBarView(
            snapshot: StatusBarSnapshot(tab: nil, tableRows: nil),
            filterState: TabFilterState(),
            selectedRowIndices: [],
            viewMode: .constant(.data),
            paginationCallbacks: PaginationCallbacks(
                onFirst: {},
                onPrevious: {},
                onNext: {},
                onLast: {},
                onPageSizeChange: { _ in },
                onShowAll: {},
                onGoToPage: { _ in },
                onRequestExactCount: {}
            ),
            columnState: StatusBarColumnState(
                hidden: [],
                all: [],
                onToggle: { _ in },
                onShowAll: {},
                onHideAll: { _ in },
                onReset: {}
            ),
            structureState: StatusBarStructureState(
                footer: StructureFooterState(),
                onAdd: {},
                onRemove: {}
            ),
            onToggleFilters: {},
            onFetchAll: nil,
            onAddRow: nil,
            onExport: nil
        )
        #expect(type(of: view.body) != Never.self)
    }

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

    @Test("Add Row button shows only in Data mode when adding is allowed")
    func addRowVisibilityByMode() {
        #expect(MainStatusBarView.showsAddRow(viewMode: .data, canAddRow: true))
        #expect(!MainStatusBarView.showsAddRow(viewMode: .structure, canAddRow: true))
        #expect(!MainStatusBarView.showsAddRow(viewMode: .json, canAddRow: true))
    }

    @Test("Add Row button is hidden when adding is not allowed")
    func addRowHiddenWhenNotAllowed() {
        #expect(!MainStatusBarView.showsAddRow(viewMode: .data, canAddRow: false))
        #expect(!MainStatusBarView.showsAddRow(viewMode: .structure, canAddRow: false))
        #expect(!MainStatusBarView.showsAddRow(viewMode: .json, canAddRow: false))
    }
}
