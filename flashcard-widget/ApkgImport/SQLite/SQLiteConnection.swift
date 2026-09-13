//
//  SQLiteConnection.swift
//  flashcard-widget
//
//  A tiny wrapper over the system SQLite3 C library (libsqlite3, part of
//  the OS -- not vendored/ported Anki code) used to read the collection
//  database extracted from a `.apkg`. Anki's own DB reading logic is not
//  used or referenced; this just runs plain SQL against the file.
//

import Foundation
import SQLite3

enum SQLiteError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

final class SQLiteConnection {
    private var db: OpaquePointer?

    init(fileURL: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        let result = sqlite3_open_v2(fileURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite open error"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.openFailed(message)
        }
        self.db = handle
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    /// Returns true if a table with this name exists in the database.
    func tableExists(_ name: String) throws -> Bool {
        let rows = try query("SELECT name FROM sqlite_master WHERE type='table' AND name = ?", bindings: [.text(name)])
        return !rows.isEmpty
    }

    enum Value {
        case text(String)
        case int(Int64)
    }

    enum Column {
        case text(String)
        case int(Int64)
        case null

        var stringValue: String {
            switch self {
            case .text(let s): return s
            case .int(let i): return String(i)
            case .null: return ""
            }
        }

        var int64Value: Int64 {
            switch self {
            case .int(let i): return i
            case .text(let s): return Int64(s) ?? 0
            case .null: return 0
            }
        }
    }

    /// Runs a query and returns each result row as an array of columns, in
    /// column order.
    func query(_ sql: String, bindings: [Value] = []) throws -> [[Column]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .int(let value):
                sqlite3_bind_int64(statement, position, value)
            }
        }

        var rows: [[Column]] = []
        loop: while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                let columnCount = sqlite3_column_count(statement)
                var row: [Column] = []
                for i in 0..<columnCount {
                    switch sqlite3_column_type(statement, i) {
                    case SQLITE_INTEGER:
                        row.append(.int(sqlite3_column_int64(statement, i)))
                    case SQLITE_NULL:
                        row.append(.null)
                    default:
                        if let cString = sqlite3_column_text(statement, i) {
                            row.append(.text(String(cString: cString)))
                        } else {
                            row.append(.null)
                        }
                    }
                }
                rows.append(row)
            case SQLITE_DONE:
                break loop
            default:
                let message = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.stepFailed(message)
            }
        }
        return rows
    }
}
