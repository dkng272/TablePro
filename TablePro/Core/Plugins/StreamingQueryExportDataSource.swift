//
//  StreamingQueryExportDataSource.swift
//  TablePro
//
import Foundation
import TableProPluginKit

final class StreamingQueryExportDataSource: PluginExportDataSource, @unchecked Sendable {
    let databaseTypeId: String

    private let query: String
    private let parameterValues: [String?]?
    private let driver: DatabaseDriver
    private let dbType: DatabaseType

    init(
        query: String,
        parameterValues: [String?]? = nil,
        driver: DatabaseDriver,
        databaseType: DatabaseType
    ) {
        self.query = query
        self.parameterValues = parameterValues
        self.driver = driver
        self.dbType = databaseType
        self.databaseTypeId = databaseType.rawValue
    }

    func streamRows(table: String, databaseName: String) -> AsyncThrowingStream<PluginStreamElement, Error> {
        guard let pluginDriver = (driver as? PluginDriverAdapter)?.schemaPluginDriver else {
            return AsyncThrowingStream { $0.finish(throwing: PluginExportError.exportFailed("No plugin driver available")) }
        }
        guard let parameterValues else {
            return pluginDriver.streamRows(query: query)
        }
        return pluginDriver.streamRows(
            query: query,
            parameters: parameterValues.map(PluginCellValue.fromOptional)
        )
    }

    func fetchApproximateRowCount(table: String, databaseName: String) async throws -> Int? {
        nil
    }

    func quoteIdentifier(_ identifier: String) -> String {
        driver.quoteIdentifier(identifier)
    }

    func escapeStringLiteral(_ value: String) -> String {
        driver.escapeStringLiteral(value)
    }

    func fetchTableDDL(table: String, databaseName: String) async throws -> String {
        ""
    }

    func execute(query: String) async throws -> PluginQueryResult {
        let result = try await driver.execute(query: query)
        return PluginQueryResult(
            columns: result.columns,
            columnTypeNames: result.columnTypes.map { $0.rawType ?? "" },
            rows: result.rows,
            rowsAffected: result.rowsAffected,
            executionTime: result.executionTime
        )
    }

    func fetchDependentSequences(table: String, databaseName: String) async throws -> [PluginSequenceInfo] {
        []
    }

    func fetchDependentTypes(table: String, databaseName: String) async throws -> [PluginEnumTypeInfo] {
        []
    }
}
