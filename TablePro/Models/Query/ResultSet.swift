import Foundation
import Observation
import os

@MainActor
@Observable
final class ResultSet: Identifiable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), label: String, tableRows: TableRows = TableRows()) {
        self.id = id
        self.label = label
        self.tableRows = tableRows
    }

    // MARK: Internal

    let id: UUID
    var label: String
    var tableRows: TableRows
    var executionTime: TimeInterval?
    var rowsAffected: Int = 0
    var errorMessage: String?
    var statusMessage: String?
    var tableName: String?
    var isEditable: Bool = false
    var isPinned: Bool = false
    var isTruncated: Bool = false
    var baseQuery: String?
    var baseQueryParameterValues: [String?]?
    var metadataVersion: Int = 0
    var sortState = SortState()
    var pagination = PaginationState()
    var columnLayout = ColumnLayoutState()
    var chartSpec: ChartSpec?

    var resultColumns: [String] {
        tableRows.columns
    }
}
