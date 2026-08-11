//
//  StreamingQueryExportDataSource.swift
//  TablePro
//
//  Streaming export data source for query results.
//  Re-executes unparameterized queries through the plugin stream. Parameterized queries use the
//  driver's existing unlimited bound-query path because the plugin stream API has no bindings overload.
//

import Foundation
import os
import TableProPluginKit

final class StreamingQueryExportDataSource: PluginExportDataSource, @unchecked Sendable {
    let databaseTypeId: String

    private let query: String
    private let parameterValues: [String?]?
    private let driver: DatabaseDriver
    private let dbType: DatabaseType

    private static let logger = Logger(subsystem: "com.TablePro", category: "StreamingQueryExport")

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
        if let parameterValues {
            return parameterizedStream(parameterValues: parameterValues)
        }
        guard let pluginDriver = (driver as? PluginDriverAdapter)?.schemaPluginDriver else {
            return AsyncThrowingStream { $0.finish(throwing: PluginExportError.exportFailed("No plugin driver available")) }
        }
        return pluginDriver.streamRows(query: query)
    }

    private func parameterizedStream(parameterValues: [String?]) -> AsyncThrowingStream<PluginStreamElement, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let parameters: [Any?] = parameterValues.map { $0 as Any? }
                    let result = try await driver.executeUserQuery(
                        query: query,
                        rowCap: nil,
                        parameters: parameters
                    )
                    continuation.yield(.header(PluginStreamHeader(
                        columns: result.columns,
                        columnTypeNames: result.columnTypes.map { $0.rawType ?? "" },
                        estimatedRowCount: result.rows.count
                    )))
                    if !result.rows.isEmpty {
                        continuation.yield(.rows(result.rows))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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
