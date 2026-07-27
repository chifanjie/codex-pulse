import Foundation
import SQLite3

final class LocalDataProvider {
    private let databasePathOverride: String?
    private let calendar: Calendar
    private let now: () -> Date
    private let rolloutScanner = RolloutScanner()

    init(
        databasePath: String? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        databasePathOverride = databasePath
        self.calendar = calendar
        self.now = now
    }

    func read() -> LocalMetrics {
        let candidates = databaseCandidates()
        guard !candidates.isEmpty else {
            return LocalMetrics(error: "未找到本地 Codex 数据")
        }

        for path in candidates {
            if let metrics = readDatabase(at: path) {
                return metrics
            }
        }
        return LocalMetrics(error: "无法读取本地 Codex 数据")
    }

    private func readDatabase(at path: String) -> LocalMetrics? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 800)

        let currentDate = now()
        guard let day = calendar.dateInterval(of: .day, for: currentDate) else {
            return nil
        }
        let activeThreshold = currentDate.addingTimeInterval(-2 * 60 * 60)
        let scanThreshold = min(day.start, activeThreshold)
        let recentThreshold = currentDate.addingTimeInterval(-7 * 24 * 60 * 60)

        guard
            let rows = readThreads(database, updatedSince: scanThreshold),
            let recentTaskCount = readRecentTaskCount(
                database,
                updatedSince: recentThreshold
            ),
            let latest = readLatestMetadata(database)
        else {
            return nil
        }

        var todayTokens: Int64 = 0
        var activeTasks: [ActiveTask] = []

        for row in rows {
            guard let summary = rolloutScanner.summary(
                at: row.rolloutPath,
                threadID: row.id,
                threadCreatedAt: row.createdAt,
                isSubagent: row.isSubagent,
                day: day
            ) else {
                continue
            }

            todayTokens = Self.addClamped(todayTokens, summary.todayTokens)

            guard
                !row.isArchived,
                summary.marker?.kind == .started,
                let lastOwnEventAt = summary.lastOwnEventAt,
                lastOwnEventAt >= activeThreshold
            else {
                continue
            }

            let title = Self.displayTitle(for: row)
            activeTasks.append(
                ActiveTask(
                    id: row.id,
                    title: title.isEmpty ? "未命名任务" : title,
                    agentName: row.agentNickname,
                    model: row.model,
                    tokensUsed: summary.currentTurnTokens,
                    startedAt: summary.marker?.timestamp ?? row.createdAt,
                    updatedAt: lastOwnEventAt,
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

        return LocalMetrics(
            todayTokens: todayTokens,
            activeTasks: activeTasks,
            recentTaskCount: recentTaskCount,
            modelName: activeTasks.first?.model ?? latest.model,
            codexVersion: latest.cliVersion
        )
    }

    private func databaseCandidates() -> [String] {
        if let databasePathOverride {
            return FileManager.default.fileExists(atPath: databasePathOverride)
                ? [databasePathOverride]
                : []
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.codex/state_5.sqlite",
            "\(home)/.codex/sqlite/state_5.sqlite",
        ].filter(FileManager.default.fileExists(atPath:))

        return candidates.sorted {
            latestThreadTimestamp(at: $0) > latestThreadTimestamp(at: $1)
        }
    }

    private func latestThreadTimestamp(at path: String) -> Int64 {
        var database: OpaquePointer?
        guard
            sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK,
            let database
        else {
            if database != nil {
                sqlite3_close(database)
            }
            return Int64.min
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database,
                "SELECT COALESCE(MAX(updated_at), 0) FROM threads",
                -1,
                &statement,
                nil
            ) == SQLITE_OK,
            let statement
        else {
            return Int64.min
        }
        defer { sqlite3_finalize(statement) }

        return sqlite3_step(statement) == SQLITE_ROW
            ? sqlite3_column_int64(statement, 0)
            : Int64.min
    }

    private func readThreads(
        _ database: OpaquePointer,
        updatedSince threshold: Date
    ) -> [ThreadRow]? {
        let sql = """
        SELECT
            id,
            rollout_path,
            created_at,
            updated_at,
            title,
            preview,
            agent_nickname,
            agent_path,
            model,
            source,
            cli_version,
            archived
        FROM threads
        WHERE updated_at >= ?1
        ORDER BY updated_at DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(threshold.timeIntervalSince1970))

        var rows: [ThreadRow] = []
        var resultCode = sqlite3_step(statement)
        while resultCode == SQLITE_ROW {
            let agentPath = Self.nonEmptyText(statement, 7)
            let source = Self.text(statement, 9) ?? ""
            let isSubagent = agentPath != nil
                || source.localizedCaseInsensitiveContains("subagent")

            rows.append(
                ThreadRow(
                    id: Self.text(statement, 0) ?? "",
                    rolloutPath: Self.text(statement, 1) ?? "",
                    createdAt: Date(
                        timeIntervalSince1970: TimeInterval(
                            sqlite3_column_int64(statement, 2)
                        )
                    ),
                    updatedAt: Date(
                        timeIntervalSince1970: TimeInterval(
                            sqlite3_column_int64(statement, 3)
                        )
                    ),
                    title: Self.text(statement, 4) ?? "",
                    preview: Self.text(statement, 5) ?? "",
                    agentNickname: Self.nonEmptyText(statement, 6),
                    agentPath: agentPath,
                    model: Self.nonEmptyText(statement, 8),
                    cliVersion: Self.nonEmptyText(statement, 10),
                    isSubagent: isSubagent,
                    isArchived: sqlite3_column_int(statement, 11) != 0
                )
            )
            resultCode = sqlite3_step(statement)
        }
        return resultCode == SQLITE_DONE ? rows : nil
    }

    private func readRecentTaskCount(
        _ database: OpaquePointer,
        updatedSince threshold: Date
    ) -> Int? {
        let sql = """
        SELECT COUNT(*)
        FROM threads
        WHERE archived = 0
          AND updated_at >= ?1
          AND (agent_path IS NULL OR agent_path = '')
          AND source NOT LIKE '%"subagent"%'
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(threshold.timeIntervalSince1970))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func readLatestMetadata(
        _ database: OpaquePointer
    ) -> (model: String?, cliVersion: String?)? {
        let sql = """
        SELECT model, cli_version
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        if result == SQLITE_DONE {
            return (nil, nil)
        }
        guard result == SQLITE_ROW else { return nil }
        return (
            Self.nonEmptyText(statement, 0),
            Self.nonEmptyText(statement, 1)
        )
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }

    private static func nonEmptyText(
        _ statement: OpaquePointer,
        _ column: Int32
    ) -> String? {
        guard let value = text(statement, column), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func displayTitle(for row: ThreadRow) -> String {
        if row.isSubagent, let agentPath = row.agentPath {
            let name = agentPath
                .split(separator: "/")
                .last
                .map(String.init)?
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            if let name, !name.isEmpty {
                return cleanTitle(name)
            }
        }
        return cleanTitle(row.title.isEmpty ? row.preview : row.title)
    }

    private static func cleanTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func addClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

private struct ThreadRow {
    let id: String
    let rolloutPath: String
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let preview: String
    let agentNickname: String?
    let agentPath: String?
    let model: String?
    let cliVersion: String?
    let isSubagent: Bool
    let isArchived: Bool
}

private final class RolloutScanner {
    struct Marker {
        enum Kind: Equatable {
            case started
            case stopped
        }

        let kind: Kind
        let timestamp: Date
    }

    struct Summary {
        let marker: Marker?
        let currentTurnTokens: Int64
        let todayTokens: Int64
        let lastOwnEventAt: Date?
    }

    private struct ScanState {
        var marker: Marker?
        var currentTurnTokens: Int64 = 0
        var todayTokens: Int64 = 0
        var lastTotalTokens: Int64?
        var lastOwnEventAt: Date?
        var ownBoundaryFound: Bool

        init(isSubagent: Bool) {
            ownBoundaryFound = !isSubagent
        }

        var summary: Summary {
            Summary(
                marker: marker,
                currentTurnTokens: currentTurnTokens,
                todayTokens: todayTokens,
                lastOwnEventAt: lastOwnEventAt
            )
        }
    }

    private struct CacheEntry {
        let fileID: UInt64?
        let size: UInt64
        let modifiedAt: Date?
        let threadCreatedAt: Date
        let threadID: String
        let isSubagent: Bool
        let day: DateInterval
        let pendingLine: Data
        let state: ScanState
    }

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]
    private let eventNeedle = Data(#""event_msg""#.utf8)
    private let sessionNeedle = Data(#""session_meta""#.utf8)

    func summary(
        at path: String,
        threadID: String,
        threadCreatedAt: Date,
        isSubagent: Bool,
        day: DateInterval
    ) -> Summary? {
        guard
            !path.isEmpty,
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let sizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }

        let size = sizeNumber.uint64Value
        let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let modifiedAt = attributes[.modificationDate] as? Date

        lock.lock()
        let previous = cache[path]
        lock.unlock()

        let sameInput = previous?.fileID == fileID
            && previous?.threadCreatedAt == threadCreatedAt
            && previous?.threadID == threadID
            && previous?.isSubagent == isSubagent
            && previous?.day == day

        if let previous,
           sameInput,
           previous.size == size,
           previous.modifiedAt == modifiedAt {
            return previous.state.summary
        }

        let canContinue = previous != nil
            && sameInput
            && size > previous!.size
        var state = canContinue
            ? previous!.state
            : ScanState(isSubagent: isSubagent)
        var pendingLine = canContinue ? previous!.pendingLine : Data()
        let lowerBound = canContinue ? previous!.size : 0

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return previous?.state.summary
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: lowerBound)
            var offset = lowerBound
            let chunkSize = 256 * 1024

            while offset < size {
                let remaining = size - offset
                let length = min(chunkSize, Int(remaining))
                guard
                    let chunk = try handle.read(upToCount: length),
                    !chunk.isEmpty
                else {
                    break
                }

                pendingLine.append(chunk)
                offset += UInt64(chunk.count)
                consumeCompleteLines(
                    from: &pendingLine,
                    state: &state,
                    threadID: threadID,
                    threadCreatedAt: threadCreatedAt,
                    isSubagent: isSubagent,
                    day: day
                )
            }
        } catch {
            return previous?.state.summary
        }

        let entry = CacheEntry(
            fileID: fileID,
            size: size,
            modifiedAt: modifiedAt,
            threadCreatedAt: threadCreatedAt,
            threadID: threadID,
            isSubagent: isSubagent,
            day: day,
            pendingLine: pendingLine,
            state: state
        )
        lock.lock()
        cache[path] = entry
        lock.unlock()
        return state.summary
    }

    private func consumeCompleteLines(
        from buffer: inout Data,
        state: inout ScanState,
        threadID: String,
        threadCreatedAt: Date,
        isSubagent: Bool,
        day: DateInterval
    ) {
        var consumedThrough = buffer.startIndex
        while let newline = buffer[consumedThrough...].firstIndex(of: 0x0A) {
            let line = buffer[consumedThrough..<newline]
            let isRelevant = line.range(of: eventNeedle) != nil
                || line.range(of: sessionNeedle) != nil
            if !line.isEmpty, isRelevant {
                consume(
                    Data(line),
                    state: &state,
                    threadID: threadID,
                    threadCreatedAt: threadCreatedAt,
                    isSubagent: isSubagent,
                    day: day
                )
            }
            consumedThrough = buffer.index(after: newline)
        }
        if consumedThrough > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<consumedThrough)
        }
    }

    private func consume(
        _ line: Data,
        state: inout ScanState,
        threadID: String,
        threadCreatedAt: Date,
        isSubagent: Bool,
        day: DateInterval
    ) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line)
                as? [String: Any],
            let recordType = object["type"] as? String,
            let payload = object["payload"] as? [String: Any]
        else {
            return
        }

        if recordType == "session_meta" {
            if payload["forked_from_id"] as? String != nil {
                state = ScanState(isSubagent: true)
            }
            return
        }

        guard
            recordType == "event_msg",
            let type = payload["type"] as? String
        else {
            return
        }

        let eventAt = Self.parseDate(object["timestamp"])
        let info = payload["info"] as? [String: Any]
        let totalUsage = info?["total_token_usage"] as? [String: Any]
        let lastUsage = info?["last_token_usage"] as? [String: Any]
        let totalTokens = Self.int64(totalUsage?["total_tokens"])
        let lastUsageTokens = Self.int64(lastUsage?["total_tokens"])

        if !state.ownBoundaryFound {
            if type == "token_count", let totalTokens {
                state.lastTotalTokens = totalTokens
                return
            }

            guard
                type == "task_started",
                Self.isOwnTurn(
                    payload,
                    threadID: threadID,
                    threadCreatedAt: threadCreatedAt
                ),
                let startedAt = Self.epochDate(payload["started_at"])
                    ?? eventAt
            else {
                return
            }

            state.ownBoundaryFound = true
            applyStarted(
                at: startedAt,
                eventAt: eventAt,
                state: &state
            )
            return
        }

        switch type {
        case "task_started":
            let startedAt = Self.epochDate(payload["started_at"])
                ?? eventAt
                ?? threadCreatedAt
            applyStarted(at: startedAt, eventAt: eventAt, state: &state)

        case "task_complete", "turn_aborted":
            let timestamp = eventAt ?? state.lastOwnEventAt ?? threadCreatedAt
            state.marker = Marker(kind: .stopped, timestamp: timestamp)
            state.lastOwnEventAt = max(state.lastOwnEventAt ?? timestamp, timestamp)

        case "token_count":
            guard let totalTokens else { return }
            let delta: Int64
            if let previous = state.lastTotalTokens {
                if totalTokens > previous {
                    delta = totalTokens - previous
                } else if totalTokens < previous {
                    delta = max(0, lastUsageTokens ?? 0)
                } else {
                    delta = 0
                }
            } else {
                delta = max(0, lastUsageTokens ?? totalTokens)
            }
            state.lastTotalTokens = totalTokens
            state.currentTurnTokens = Self.addClamped(
                state.currentTurnTokens,
                delta
            )
            if let eventAt, day.contains(eventAt) {
                state.todayTokens = Self.addClamped(state.todayTokens, delta)
            }
            if let eventAt {
                state.lastOwnEventAt = max(
                    state.lastOwnEventAt ?? eventAt,
                    eventAt
                )
            }

        default:
            break
        }
    }

    private func applyStarted(
        at startedAt: Date,
        eventAt: Date?,
        state: inout ScanState
    ) {
        state.marker = Marker(kind: .started, timestamp: startedAt)
        state.currentTurnTokens = 0
        let activityAt = eventAt ?? startedAt
        state.lastOwnEventAt = max(state.lastOwnEventAt ?? activityAt, activityAt)
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return ISO8601DateFormatter.fractional.date(from: value)
            ?? ISO8601DateFormatter.standard.date(from: value)
    }

    private static func epochDate(_ value: Any?) -> Date? {
        int64(value).map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
    }

    private static func isOwnTurn(
        _ payload: [String: Any],
        threadID: String,
        threadCreatedAt: Date
    ) -> Bool {
        if let turnID = payload["turn_id"] as? String,
           isUUIDv7(turnID),
           isUUIDv7(threadID) {
            return turnID.lowercased() >= threadID.lowercased()
        }

        guard let startedAt = epochDate(payload["started_at"]) else {
            return false
        }
        return startedAt >= threadCreatedAt
    }

    private static func isUUIDv7(_ value: String) -> Bool {
        let normalized = value.lowercased()
        guard normalized.count == 36 else { return false }
        let characters = Array(normalized)
        return characters[8] == "-"
            && characters[13] == "-"
            && characters[14] == "7"
            && characters[18] == "-"
            && characters[23] == "-"
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private static func addClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
