//
//  LibPQSingleRowStreamStateTests.swift
//  TableProTests
//

import TableProPluginKit
import Testing

@Suite("LibPQ native single-row streaming")
struct LibPQSingleRowStreamStateTests {
    @Test("Multiple tuples emit one complete header and preserve every row")
    func multipleTuplesEmitOneHeader() throws {
        let nativeTuples: [(columns: [String], oids: [UInt32], types: [String], row: PluginRow)] = [
            (["id", "name"], [23, 25], ["integer", "text"], ["1", "Ada"]),
            (["id", "name"], [23, 25], ["integer", "text"], ["2", "Grace"]),
            (["id", "name"], [23, 25], ["integer", "text"], ["3", "Linus"]),
        ]
        var state = LibPQSingleRowStreamState(batchSize: 2)
        var elements: [PluginStreamElement] = []

        for tuple in nativeTuples {
            if let header = state.header(
                columns: tuple.columns,
                columnOids: tuple.oids,
                columnTypeNames: tuple.types,
                estimatedRowCount: nil
            ) {
                elements.append(.header(header))
            }
            if let batch = state.append(tuple.row) {
                elements.append(.rows(batch))
            }
        }
        if let batch = state.flush() {
            elements.append(.rows(batch))
        }

        let headers = elements.compactMap { element -> PluginStreamHeader? in
            guard case .header(let header) = element else { return nil }
            return header
        }
        let rows = elements.flatMap { element -> [PluginRow] in
            guard case .rows(let batch) = element else { return [] }
            return batch
        }

        let header = try #require(headers.first)
        #expect(headers.count == 1)
        #expect(header.columns == ["id", "name"])
        #expect(header.columnTypeNames == ["integer", "text"])
        #expect(header.estimatedRowCount == nil)
        #expect(rows == [["1", "Ada"], ["2", "Grace"], ["3", "Linus"]])
        #expect(state.columnOids == [23, 25])
    }
}
