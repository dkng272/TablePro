//
//  ExecuteUserQueryTests.swift
//  TableProTests
//

import Foundation
import Testing
import TableProPluginKit
@testable import TablePro

@Suite("executeUserQuery applies row cap and respects user SQL")
struct ExecuteUserQueryTests {

    @Test("Caps result at rowCap and marks isTruncated when there are more rows than the cap")
    func capsAndMarksTruncated() async throws {
        let rows = (1...100).map { ["row_\($0)"] }
        let driver = StubPluginDriver(rows: rows)

        let result = try await driver.executeUserQuery(query: "SELECT * FROM t", rowCap: 5, parameters: nil)

        #expect(result.rows.count == 5)
        #expect(result.isTruncated)
        #expect(result.rows.first?.first == "row_1")
        #expect(result.rows.last?.first == "row_5")
    }

    @Test("Returns full result without truncation flag when row count is below cap")
    func belowCapNotTruncated() async throws {
        let rows = (1...3).map { ["row_\($0)"] }
        let driver = StubPluginDriver(rows: rows)

        let result = try await driver.executeUserQuery(query: "SELECT * FROM t", rowCap: 5, parameters: nil)

        #expect(result.rows.count == 3)
        #expect(!result.isTruncated)
    }

    @Test("Returns full result when rowCap is nil")
    func unlimitedCap() async throws {
        let rows = (1...100).map { ["row_\($0)"] }
        let driver = StubPluginDriver(rows: rows)

        let result = try await driver.executeUserQuery(query: "SELECT * FROM t", rowCap: nil, parameters: nil)

        #expect(result.rows.count == 100)
        #expect(!result.isTruncated)
    }

    @Test("Treats rowCap of 0 as unlimited and returns the full result")
    func zeroCapMeansUnlimited() async throws {
        let rows = (1...100).map { ["row_\($0)"] }
        let driver = StubPluginDriver(rows: rows)

        let result = try await driver.executeUserQuery(query: "SELECT * FROM t", rowCap: 0, parameters: nil)

        #expect(result.rows.count == 100)
        #expect(!result.isTruncated)
    }

    @Test("Passes user SQL through unchanged regardless of cap")
    func passesUserSqlUnchanged() async throws {
        let driver = StubPluginDriver(rows: [["x"]])
        let userSql = "SELECT uuid FROM TMTask WHERE status IN (2,3) ORDER BY stopDate DESC LIMIT 10"

        _ = try await driver.executeUserQuery(query: userSql, rowCap: 10_000, parameters: nil)

        #expect(driver.lastExecutedQuery == userSql)
        #expect(!driver.lastExecutedQuery!.contains("OFFSET"))
        #expect(driver.lastExecutedQuery!.contains("LIMIT 10"))
    }

    @Test("Passes user SQL with CTE unchanged")
    func passesCteUnchanged() async throws {
        let driver = StubPluginDriver(rows: [["x"]])
        let userSql = "WITH cte AS (SELECT * FROM t LIMIT 5) SELECT * FROM cte"

        _ = try await driver.executeUserQuery(query: userSql, rowCap: 10_000, parameters: nil)

        #expect(driver.lastExecutedQuery == userSql)
    }

    @Test("Passes SQL with an app-appended LIMIT through byte-for-byte and still caps post-fetch")
    func passesInjectedLimitSqlUnchanged() async throws {
        let rows = (1...6).map { ["row_\($0)"] }
        let driver = StubPluginDriver(rows: rows)
        let injectedSql = "SELECT * FROM t LIMIT 6"

        let result = try await driver.executeUserQuery(query: injectedSql, rowCap: 5, parameters: nil)

        #expect(driver.lastExecutedQuery == injectedSql)
        #expect(result.rows.count == 5)
        #expect(result.isTruncated)
    }

    @Test("Routes parameterized queries through executeParameterized with the same SQL")
    func parameterizedRoutesCorrectly() async throws {
        let driver = StubPluginDriver(rows: [["x"]])
        let userSql = "SELECT * FROM t WHERE id = ? LIMIT 3"

        _ = try await driver.executeUserQuery(query: userSql, rowCap: 100, parameters: ["42"])

        #expect(driver.lastExecutedQuery == userSql)
        #expect(driver.lastParameters == ["42"])
    }

    @Test("Preserves status message and execution metadata when truncating")
    func preservesMetadata() async throws {
        let rows = (1...10).map { ["row_\($0)"] }
        let driver = StubPluginDriver(rows: rows, statusMessage: "warning: cache miss")

        let result = try await driver.executeUserQuery(query: "SELECT * FROM t", rowCap: 3, parameters: nil)

        #expect(result.rows.count == 3)
        #expect(result.isTruncated)
        #expect(result.statusMessage == "warning: cache miss")
        #expect(result.rowsAffected == 0)
    }

    @Test("Streaming query export preserves bindings, metadata, and every batch beyond the chart sample limit")
    func streamingExportPreservesParametersAndBatches() async throws {
        #expect(ChartDataBuilder.defaultPointLimit == 5_000)
        let rows = (1...5_001).map { [String($0), nil] }
        let pluginDriver = StubPluginDriver(
            rows: rows,
            columns: ["id", "deleted_at"],
            columnTypeNames: ["INTEGER", "TIMESTAMP"],
            streamBatchSize: 3_000
        )
        let adapter = PluginDriverAdapter(
            connection: TestFixtures.makeConnection(type: .sqlite),
            pluginDriver: pluginDriver
        )
        let dataSource = StreamingQueryExportDataSource(
            query: "SELECT value FROM records WHERE id = ? AND deleted_at IS ?",
            parameterValues: ["42", nil],
            driver: adapter,
            databaseType: .sqlite
        )

        var elements: [PluginStreamElement] = []
        for try await element in dataSource.streamRows(table: "query", databaseName: "") {
            elements.append(element)
        }

        #expect(elements.count == 3)
        if case .header(let header) = elements[0] {
            #expect(header.columns == ["id", "deleted_at"])
            #expect(header.columnTypeNames == ["INTEGER", "TIMESTAMP"])
        } else {
            Issue.record("Expected a stream header")
        }
        let batches = elements.dropFirst().compactMap { element -> [PluginRow]? in
            guard case .rows(let rows) = element else { return nil }
            return rows
        }
        #expect(batches.map(\.count) == [3_000, 2_001])
        #expect(batches.flatMap { $0 }.count == 5_001)
        #expect(pluginDriver.lastExecutedQuery == "SELECT value FROM records WHERE id = ? AND deleted_at IS ?")
        #expect(pluginDriver.lastStreamingParameters == [.text("42"), .null])
        #expect(pluginDriver.executeParameterizedCallCount == 0)
    }

    @Test("Unbound streaming query export keeps the existing stream path")
    func streamingExportWithoutParametersUsesLegacyStream() async throws {
        let pluginDriver = StubPluginDriver(rows: [["unbound"]])
        let adapter = PluginDriverAdapter(
            connection: TestFixtures.makeConnection(type: .sqlite),
            pluginDriver: pluginDriver
        )
        let dataSource = StreamingQueryExportDataSource(
            query: "SELECT value FROM records",
            driver: adapter,
            databaseType: .sqlite
        )

        for try await _ in dataSource.streamRows(table: "query", databaseName: "") {}

        #expect(pluginDriver.unboundStreamCallCount == 1)
        #expect(pluginDriver.lastStreamingParameters == nil)
        #expect(pluginDriver.executeParameterizedCallCount == 0)
    }

    @Test("Legacy plugins fail closed instead of interpolating or materializing bound exports")
    func legacyPluginRejectsParameterizedStreaming() async {
        let driver: any PluginDatabaseDriver = LegacyStreamingStubPluginDriver()

        do {
            for try await _ in driver.streamRows(query: "SELECT ?", parameters: [.text("bound")]) {}
            Issue.record("Expected parameterized streaming to be rejected")
        } catch {
            #expect(error.localizedDescription.contains("parameterized streaming"))
        }
    }

    @Test("Cancelling a bound export terminates its plugin producer")
    func cancellingParameterizedExportStopsProducer() async throws {
        let pluginDriver = CancellableStreamingStubPluginDriver()
        let adapter = PluginDriverAdapter(
            connection: TestFixtures.makeConnection(type: .sqlite),
            pluginDriver: pluginDriver
        )
        let dataSource = StreamingQueryExportDataSource(
            query: "SELECT value FROM records WHERE id = ?",
            parameterValues: ["42"],
            driver: adapter,
            databaseType: .sqlite
        )

        let consumer = Task {
            for try await _ in dataSource.streamRows(table: "query", databaseName: "") {}
        }
        #expect(await pluginDriver.awaitProducerStart())

        consumer.cancel()
        _ = try? await consumer.value

        #expect(await pluginDriver.awaitProducerCancellation())
        pluginDriver.releaseBlockedExecution()
    }
}

private final class StubPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    private(set) var lastExecutedQuery: String?
    private(set) var lastParameters: [PluginCellValue]?
    private(set) var lastStreamingParameters: [PluginCellValue]?
    private(set) var executeParameterizedCallCount = 0
    private(set) var unboundStreamCallCount = 0
    private let rowsToReturn: [[PluginCellValue]]
    private let columns: [String]
    private let columnTypeNames: [String]
    private let streamBatchSize: Int
    private let statusMessage: String?

    init(
        rows: [[String?]],
        columns: [String] = ["col1"],
        columnTypeNames: [String] = ["TEXT"],
        streamBatchSize: Int = 5_000,
        statusMessage: String? = nil
    ) {
        self.rowsToReturn = rows.map { row in row.map(PluginCellValue.fromOptional) }
        self.columns = columns
        self.columnTypeNames = columnTypeNames
        self.streamBatchSize = streamBatchSize
        self.statusMessage = statusMessage
    }

    func connect() async throws {}
    func disconnect() {}

    func execute(query: String) async throws -> PluginQueryResult {
        lastExecutedQuery = query
        return PluginQueryResult(
            columns: columns,
            columnTypeNames: columnTypeNames,
            rows: rowsToReturn,
            rowsAffected: 0,
            executionTime: 0.001,
            statusMessage: statusMessage
        )
    }

    func executeParameterized(query: String, parameters: [PluginCellValue]) async throws -> PluginQueryResult {
        executeParameterizedCallCount += 1
        lastExecutedQuery = query
        lastParameters = parameters
        return PluginQueryResult(
            columns: columns,
            columnTypeNames: columnTypeNames,
            rows: rowsToReturn,
            rowsAffected: 0,
            executionTime: 0.001,
            statusMessage: statusMessage
        )
    }

    func streamRows(query: String) -> AsyncThrowingStream<PluginStreamElement, Error> {
        unboundStreamCallCount += 1
        return makeStream()
    }

    func streamRows(
        query: String,
        parameters: [PluginCellValue]
    ) -> AsyncThrowingStream<PluginStreamElement, Error> {
        lastExecutedQuery = query
        lastStreamingParameters = parameters
        return makeStream()
    }

    private func makeStream() -> AsyncThrowingStream<PluginStreamElement, Error> {
        let columns = columns
        let columnTypeNames = columnTypeNames
        let batches = rowsToReturn.chunked(into: streamBatchSize)
        return AsyncThrowingStream { continuation in
            continuation.yield(.header(PluginStreamHeader(
                columns: columns,
                columnTypeNames: columnTypeNames
            )))
            for batch in batches {
                continuation.yield(.rows(batch))
            }
            continuation.finish()
        }
    }

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] { [] }
    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] { [] }
    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] { [] }
    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] { [] }
    func fetchTableDDL(table: String, schema: String?) async throws -> String { "" }
    func fetchViewDefinition(view: String, schema: String?) async throws -> String { "" }
    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table)
    }
    func fetchDatabases() async throws -> [String] { [] }
    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }
}

private final class LegacyStreamingStubPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    func connect() async throws {}
    func disconnect() {}
    func execute(query: String) async throws -> PluginQueryResult { .empty }
    func executeParameterized(query: String, parameters: [PluginCellValue]) async throws -> PluginQueryResult { .empty }
    func fetchTables(schema: String?) async throws -> [PluginTableInfo] { [] }
    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] { [] }
    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] { [] }
    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] { [] }
    func fetchTableDDL(table: String, schema: String?) async throws -> String { "" }
    func fetchViewDefinition(view: String, schema: String?) async throws -> String { "" }
    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table)
    }
    func fetchDatabases() async throws -> [String] { [] }
    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }
}

private final class CancellableStreamingStubPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var producerStarted = false
    private var producerCancelled = false
    private var releaseExecution = false

    func connect() async throws {}
    func disconnect() {}
    func execute(query: String) async throws -> PluginQueryResult { .empty }

    func executeParameterized(query: String, parameters: [PluginCellValue]) async throws -> PluginQueryResult {
        lock.withLock { producerStarted = true }
        while !lock.withLock({ releaseExecution }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        return .empty
    }

    func streamRows(
        query: String,
        parameters: [PluginCellValue]
    ) -> AsyncThrowingStream<PluginStreamElement, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                self.lock.withLock { self.producerStarted = true }
                continuation.yield(.header(PluginStreamHeader(columns: ["value"], columnTypeNames: ["TEXT"])))
                do {
                    try await Task.sleep(for: .seconds(30))
                    continuation.finish()
                } catch is CancellationError {
                    self.lock.withLock { self.producerCancelled = true }
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    func awaitProducerStart() async -> Bool {
        await waitUntil { self.lock.withLock { self.producerStarted } }
    }

    func awaitProducerCancellation() async -> Bool {
        await waitUntil { self.lock.withLock { self.producerCancelled } }
    }

    func releaseBlockedExecution() {
        lock.withLock { releaseExecution = true }
    }

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] { [] }
    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] { [] }
    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] { [] }
    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] { [] }
    func fetchTableDDL(table: String, schema: String?) async throws -> String { "" }
    func fetchViewDefinition(view: String, schema: String?) async throws -> String { "" }
    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table)
    }
    func fetchDatabases() async throws -> [String] { [] }
    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }

    private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
