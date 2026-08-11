//
//  LibPQSingleRowStreamState.swift
//  PostgreSQLDriverPlugin
//

import TableProPluginKit

struct LibPQSingleRowStreamState {
    private(set) var columnOids: [UInt32] = []
    private(set) var headerSent = false
    private let batchSize: Int
    private var batch: [PluginRow]

    init(batchSize: Int = 5_000) {
        self.batchSize = batchSize
        batch = []
        batch.reserveCapacity(batchSize)
    }

    mutating func header(
        columns: [String],
        columnOids: [UInt32],
        columnTypeNames: [String],
        estimatedRowCount: Int?
    ) -> PluginStreamHeader? {
        guard !headerSent else { return nil }
        self.columnOids = columnOids
        headerSent = true
        return PluginStreamHeader(
            columns: columns,
            columnTypeNames: columnTypeNames,
            estimatedRowCount: estimatedRowCount
        )
    }

    mutating func append(_ row: PluginRow) -> [PluginRow]? {
        batch.append(row)
        guard batch.count >= batchSize else { return nil }
        let rows = batch
        batch.removeAll(keepingCapacity: true)
        return rows
    }

    mutating func flush() -> [PluginRow]? {
        guard !batch.isEmpty else { return nil }
        let rows = batch
        batch.removeAll(keepingCapacity: true)
        return rows
    }
}
