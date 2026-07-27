import Foundation
import SQLite3

final class LocalDataProvider {
    private let databasePath: String?
    private let markerScanner = TaskMarkerScanner()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.codex/state_5.sqlite",
            "\(home)/.codex/sqlite/state_5.sqlite",
        ]
        databasePath = candidates.first(where: FileManager.default.fileExists(atPath:))
    }

    func read() -> LocalMetrics {
        guard let databasePath else {
            return LocalMetrics(error: "未找到本地 Codex 数据")
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if database != nil {
                sqlite3_close(database)
            }
            return LocalMetrics(error: "无法读取本地 Codex 数据")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 800)

        guard
            let rows = readThreads(database),
            let todayTokens = readTodayTokens(database)
        else {
            return LocalMetrics(error: "本地 Codex 数据格式不兼容")
        }
        let now = Date()
        let recentThreshold = now.addingTimeInterval(-7 * 24 * 60 * 60)

        var activeTasks: [ActiveTask] = []
        for row in rows.prefix(60) {
            let fileUpdatedAt = Self.fileModifiedAt(row.rolloutPath)
            let lastActivityAt = max(row.updatedAt, fileUpdatedAt ?? row.updatedAt)
            guard lastActivityAt > now.addingTimeInterval(-24 * 60 * 60) else {
                continue
            }

            let marker = markerScanner.lastTaskMarker(at: row.rolloutPath)
            let activityAge = now.timeIntervalSince(lastActivityAt)
            let isActive = (marker?.kind == .started && activityAge < 30 * 60)
                || (marker == nil && activityAge < 30)
            guard isActive else { continue }

            let title = Self.cleanTitle(row.title.isEmpty ? row.preview : row.title)
            activeTasks.append(
                ActiveTask(
                    id: row.id,
                    title: title.isEmpty ? "未命名任务" : title,
                    agentName: row.agentNickname,
                    model: row.model,
                    tokensUsed: row.tokensUsed,
                    startedAt: marker?.timestamp ?? row.createdAt,
                    updatedAt: lastActivityAt,
                    isSubagent: row.isSubagent
                )
            )
        }

        activeTasks.sort {
            if $0.isSubagent != $1.isSubagent {
                return !$0.isSubagent
            }
            return $0.updatedAt > $1.updatedAt
        }

        let latest = rows.first
        return LocalMetrics(
            todayTokens: todayTokens,
            activeTasks: activeTasks,
            recentTaskCount: rows.filter { $0.updatedAt >= recentThreshold }.count,
            modelName: activeTasks.first?.model ?? latest?.model,
            codexVersion: latest?.cliVersion
        )
    }

    private func readThreads(_ database: OpaquePointer) -> [ThreadRow]? {
        let sql = """
        SELECT
            id,
            rollout_path,
            created_at,
            updated_at,
            title,
            preview,
            tokens_used,
            agent_nickname,
            agent_path,
            model,
            source,
            cli_version
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at DESC
        LIMIT 160
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var rows: [ThreadRow] = []
        var resultCode = sqlite3_step(statement)
        while resultCode == SQLITE_ROW {
            let id = Self.text(statement, 0) ?? ""
            let rolloutPath = Self.text(statement, 1) ?? ""
            let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)))
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3)))
            let title = Self.text(statement, 4) ?? ""
            let preview = Self.text(statement, 5) ?? ""
            let tokensUsed = sqlite3_column_int64(statement, 6)
            let agentNickname = Self.text(statement, 7)
            let agentPath = Self.text(statement, 8)
            let model = Self.text(statement, 9)
            let source = Self.text(statement, 10) ?? ""
            let cliVersion = Self.text(statement, 11)
            let isSubagent = agentPath != nil || source.localizedCaseInsensitiveContains("subagent")

            rows.append(
                ThreadRow(
                    id: id,
                    rolloutPath: rolloutPath,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    title: title,
                    preview: preview,
                    tokensUsed: tokensUsed,
                    agentNickname: agentNickname,
                    model: model,
                    cliVersion: cliVersion,
                    isSubagent: isSubagent
                )
            )
            resultCode = sqlite3_step(statement)
        }
        return resultCode == SQLITE_DONE ? rows : nil
    }

    private func readTodayTokens(_ database: OpaquePointer) -> Int64? {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(24 * 60 * 60)

        let sql = """
        SELECT COALESCE(SUM(tokens_used), 0)
        FROM threads
        WHERE created_at >= ?1 AND created_at < ?2
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(startOfToday.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(startOfTomorrow.timeIntervalSince1970))

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }

    private static func cleanTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func fileModifiedAt(_ path: String) -> Date? {
        guard !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }
}

private struct ThreadRow {
    let id: String
    let rolloutPath: String
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let preview: String
    let tokensUsed: Int64
    let agentNickname: String?
    let model: String?
    let cliVersion: String?
    let isSubagent: Bool
}

private final class TaskMarkerScanner {
    struct Marker {
        enum Kind {
            case started
            case stopped
        }

        let kind: Kind
        let timestamp: Date?
    }

    private struct CacheEntry {
        let size: UInt64
        let marker: Marker?
    }

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]

    private let markerPatterns: [(Data, Marker.Kind)] = [
        (Data(#""type":"event_msg","payload":{"type":"task_started""#.utf8), .started),
        (Data(#""type":"event_msg","payload":{"type":"task_complete""#.utf8), .stopped),
        (Data(#""type":"event_msg","payload":{"type":"turn_aborted""#.utf8), .stopped),
    ]

    func lastTaskMarker(at path: String) -> Marker? {
        guard !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let sizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }

        let size = sizeNumber.uint64Value
        lock.lock()
        let cached = cache[path]
        lock.unlock()

        if let cached, cached.size == size {
            return cached.marker
        }

        let marker: Marker?
        if let cached, size > cached.size {
            marker = scanRange(
                path: path,
                lowerBound: cached.size > 256 ? cached.size - 256 : 0,
                upperBound: size
            ) ?? cached.marker
        } else {
            marker = scanBackwards(path: path, size: size)
        }

        lock.lock()
        cache[path] = CacheEntry(size: size, marker: marker)
        lock.unlock()
        return marker
    }

    private func scanBackwards(path: String, size: UInt64) -> Marker? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 1_048_576
        let overlap: UInt64 = 256
        var upperBound = size

        while upperBound > 0 {
            let lowerBound = upperBound > chunkSize ? upperBound - chunkSize : 0
            if let marker = scan(handle: handle, lowerBound: lowerBound, upperBound: upperBound) {
                return marker
            }
            if lowerBound == 0 {
                break
            }
            upperBound = lowerBound + overlap
        }
        return nil
    }

    private func scanRange(path: String, lowerBound: UInt64, upperBound: UInt64) -> Marker? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return scan(handle: handle, lowerBound: lowerBound, upperBound: upperBound)
    }

    private func scan(
        handle: FileHandle,
        lowerBound: UInt64,
        upperBound: UInt64
    ) -> Marker? {
        guard upperBound > lowerBound else { return nil }

        do {
            try handle.seek(toOffset: lowerBound)
            let length = Int(upperBound - lowerBound)
            guard let data = try handle.read(upToCount: length), !data.isEmpty else {
                return nil
            }

            var bestRange: Range<Data.Index>?
            var bestKind: Marker.Kind?

            for (pattern, kind) in markerPatterns {
                guard let range = data.range(of: pattern, options: .backwards) else {
                    continue
                }
                if bestRange == nil || range.lowerBound > bestRange!.lowerBound {
                    bestRange = range
                    bestKind = kind
                }
            }

            guard let bestRange, let bestKind else { return nil }
            let timestamp = timestampNearMarker(in: data, markerOffset: bestRange.lowerBound)
            return Marker(kind: bestKind, timestamp: timestamp)
        } catch {
            return nil
        }
    }

    private func timestampNearMarker(in data: Data, markerOffset: Data.Index) -> Date? {
        let lineStart = data[..<markerOffset].lastIndex(of: 0x0A).map {
            data.index(after: $0)
        } ?? data.startIndex
        let lineEnd = data[markerOffset...].firstIndex(of: 0x0A) ?? data.endIndex
        guard lineStart < lineEnd else { return nil }

        let line = Data(data[lineStart..<lineEnd])
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let value = object["timestamp"] as? String
        else {
            return nil
        }
        return ISO8601DateFormatter.fractional.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
