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

    @Test("Chart and query-result export labels are localized")
    func chartAndExportLabelsAreLocalized() {
        let translations = [
            (
                localizedString("Chart", locale: "tr"),
                localizedString("Export Query Results", locale: "tr"),
                "Grafik",
                "Sorgu Sonuçlarını Dışa Aktar"
            ),
            (
                localizedString("Chart", locale: "vi"),
                localizedString("Export Query Results", locale: "vi"),
                "Biểu đồ",
                "Xuất kết quả truy vấn"
            ),
            (
                localizedString("Chart", locale: "zh-Hans"),
                localizedString("Export Query Results", locale: "zh-Hans"),
                "图表",
                "导出查询结果"
            ),
            (
                localizedString("Chart", locale: "zh-Hant"),
                localizedString("Export Query Results", locale: "zh-Hant"),
                "圖表",
                "匯出查詢結果"
            ),
        ]

        for (chart, export, expectedChart, expectedExport) in translations {
            #expect(chart == expectedChart)
            #expect(export == expectedExport)
        }
    }

    @Test("Export action opens for a header-only query result")
    func headerOnlyResultOpensExportAction() {
        let connection = TestFixtures.makeConnection()
        let tabManager = QueryTabManager()
        tabManager.addTab(databaseName: connection.database)
        let coordinator = MainContentCoordinator(
            connection: connection,
            tabManager: tabManager,
            changeManager: DataChangeManager(),
            toolbarState: ConnectionToolbarState()
        )
        defer { coordinator.teardown() }

        guard let tabId = tabManager.selectedTabId else {
            Issue.record("Expected a selected query tab")
            return
        }
        coordinator.setActiveTableRows(
            TableRows.from(
                queryRows: [],
                columns: ["id"],
                columnTypes: [.integer(rawType: "INTEGER")]
            ),
            for: tabId
        )

        coordinator.openExportQueryResultsDialog()

        guard case .exportQueryResults? = coordinator.activeSheet else {
            Issue.record("Expected the query-result export sheet")
            return
        }
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

private func localizedString(_ key: String, locale: String) -> String {
    guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        return key
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}
