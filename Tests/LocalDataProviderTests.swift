import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

@main
enum LocalDataProviderTests {
    static func main() throws {
        try testDailyDeltasForksAndActivity()
        try testRecentCountHasNoRowLimit()
        try testLegacyWidgetSnapshotCompatibility()
        print("LocalDataProvider regression tests passed")
    }

    private static func testDailyDeltasForksAndActivity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = try date("2026-07-27T08:30:00.000Z")
        let day = calendar.dateInterval(of: .day, for: now)!

        let completedPath = fixture.rolloutPath("completed-root")
        try writeEvents(
            [
                event(
                    at: day.start.addingTimeInterval(-2),
                    type: "task_started",
                    startedAt: day.start.addingTimeInterval(-2)
                ),
                event(
                    at: day.start.addingTimeInterval(-1),
                    type: "token_count",
                    total: 100,
                    last: 100
                ),
                event(
                    at: day.start,
                    type: "token_count",
                    total: 160,
                    last: 60
                ),
                event(
                    at: day.start.addingTimeInterval(1),
                    type: "token_count",
                    total: 160,
                    last: 10
                ),
                event(
                    at: day.start.addingTimeInterval(2),
                    type: "task_complete"
                ),
            ],
            to: completedPath
        )
        try fixture.insertThread(
            id: "completed-root",
            path: completedPath,
            createdAt: day.start.addingTimeInterval(-3_600),
            updatedAt: now,
            title: "Completed root"
        )

        let childCreatedAt = now.addingTimeInterval(-10 * 60)
        let childID = uuidV7(at: childCreatedAt, suffix: "000000000001")
        let childParentTurnID = uuidV7(
            at: childCreatedAt.addingTimeInterval(-60),
            suffix: "000000000002"
        )
        let childOwnTurnID = uuidV7(
            at: childCreatedAt.addingTimeInterval(1),
            suffix: "000000000003"
        )
        let childPath = fixture.rolloutPath(childID)
        try writeEvents(
            [
                event(
                    at: childCreatedAt,
                    type: "task_started",
                    startedAt: childCreatedAt.addingTimeInterval(-3_600),
                    turnID: childParentTurnID
                ),
                event(
                    at: childCreatedAt,
                    type: "token_count",
                    total: 100,
                    last: 100
                ),
                event(
                    at: childCreatedAt,
                    type: "token_count",
                    total: 200,
                    last: 100
                ),
                event(
                    at: childCreatedAt,
                    type: "task_complete"
                ),
                event(
                    at: childCreatedAt.addingTimeInterval(1),
                    type: "task_started",
                    startedAt: childCreatedAt,
                    turnID: childOwnTurnID
                ),
                event(
                    at: childCreatedAt.addingTimeInterval(2),
                    type: "token_count",
                    total: 250,
                    last: 50
                ),
                event(
                    at: childCreatedAt.addingTimeInterval(3),
                    type: "token_count",
                    total: 250,
                    last: 25
                ),
                event(
                    at: childCreatedAt.addingTimeInterval(4),
                    type: "token_count",
                    total: 300,
                    last: 50
                ),
            ],
            to: childPath
        )
        try fixture.insertThread(
            id: childID,
            path: childPath,
            createdAt: childCreatedAt,
            updatedAt: now,
            title: "Inherited parent title",
            agentPath: "/root/stats_accuracy"
        )

        let userForkCreatedAt = now.addingTimeInterval(-20 * 60)
        let userForkID = uuidV7(
            at: userForkCreatedAt,
            suffix: "000000000010"
        )
        let userForkPath = fixture.rolloutPath(userForkID)
        try writeEvents(
            [
                sessionMeta(forkedFromID: "parent-thread"),
                event(
                    at: userForkCreatedAt,
                    type: "task_started",
                    startedAt: userForkCreatedAt.addingTimeInterval(-120),
                    turnID: uuidV7(
                        at: userForkCreatedAt.addingTimeInterval(-120),
                        suffix: "000000000011"
                    )
                ),
                event(
                    at: userForkCreatedAt,
                    type: "token_count",
                    total: 100,
                    last: 100
                ),
                event(
                    at: userForkCreatedAt,
                    type: "token_count",
                    total: 200,
                    last: 100
                ),
                event(
                    at: userForkCreatedAt,
                    type: "task_complete"
                ),
                event(
                    at: userForkCreatedAt.addingTimeInterval(1),
                    type: "task_started",
                    startedAt: userForkCreatedAt,
                    turnID: uuidV7(
                        at: userForkCreatedAt.addingTimeInterval(1),
                        suffix: "000000000012"
                    )
                ),
                event(
                    at: userForkCreatedAt.addingTimeInterval(2),
                    type: "token_count",
                    total: 250,
                    last: 50
                ),
                event(
                    at: userForkCreatedAt.addingTimeInterval(3),
                    type: "task_complete"
                ),
            ],
            to: userForkPath
        )
        try fixture.insertThread(
            id: userForkID,
            path: userForkPath,
            createdAt: userForkCreatedAt,
            updatedAt: now,
            title: "User fork"
        )

        for index in 0..<7 {
            let id = "active-root-\(index)"
            let path = fixture.rolloutPath(id)
            let startedAt = now.addingTimeInterval(
                -5 * 60 + TimeInterval(index)
            )
            var events = [
                    event(
                        at: startedAt,
                        type: "task_started",
                        startedAt: startedAt
                    ),
                    event(
                        at: startedAt.addingTimeInterval(1),
                        type: "token_count",
                        total: 10,
                        last: 10
                    ),
                ]
            if index == 0 {
                let secondStart = now.addingTimeInterval(-60)
                events.append(
                    event(
                        at: secondStart.addingTimeInterval(-1),
                        type: "task_complete"
                    )
                )
                events.append(
                    event(
                        at: secondStart,
                        type: "task_started",
                        startedAt: secondStart
                    )
                )
                events.append(
                    event(
                        at: secondStart.addingTimeInterval(1),
                        type: "token_count",
                        total: 15,
                        last: 5
                    )
                )
            }
            try writeEvents(events, to: path)
            try fixture.insertThread(
                id: id,
                path: path,
                createdAt: startedAt,
                updatedAt: now,
                title: "Active \(index)"
            )
        }

        let stalePath = fixture.rolloutPath("stale-child")
        let staleStartedAt = now.addingTimeInterval(-3 * 60 * 60)
        try writeEvents(
            [
                event(
                    at: staleStartedAt,
                    type: "task_started",
                    startedAt: staleStartedAt
                ),
            ],
            to: stalePath
        )
        try fixture.insertThread(
            id: "stale-child",
            path: stalePath,
            createdAt: staleStartedAt,
            updatedAt: now,
            title: "Stale child",
            agentPath: "/root/stale_child"
        )
        fixture.closeDatabase()

        let provider = LocalDataProvider(
            databasePath: fixture.databasePath,
            calendar: calendar,
            now: { now }
        )
        let first = provider.read()
        try expect(first.error == nil, "fixture should be readable")
        try expect(
            first.todayTokens == 285,
            "today should exclude fork replay and include actual deltas, got \(first.todayTokens)"
        )
        try expect(
            first.activeTasks.count == 8,
            "expected 8 active tasks, got \(first.activeTasks.count)"
        )
        try expect(
            first.recentTaskCount == 9,
            "recent root count should exclude subagents without a row cap"
        )

        guard let child = first.activeTasks.first(where: { $0.id == childID }) else {
            throw TestFailure("fork child should be active")
        }
        try expect(
            child.tokensUsed == 100,
            "fork child should exclude its inherited 200-token baseline"
        )
        try expect(
            child.title == "stats accuracy",
            "child title should come from its own agent path"
        )
        try expect(
            !first.activeTasks.contains(where: { $0.id == "completed-root" }),
            "a completed root must not be active"
        )
        try expect(
            !first.activeTasks.contains(where: { $0.id == "stale-child" }),
            "a started marker with no own event for two hours must expire"
        )
        try expect(
            !first.activeTasks.contains(where: { $0.id == userForkID }),
            "a completed user-created fork must not be active"
        )
        let restarted = first.activeTasks.first { $0.id == "active-root-0" }
        try expect(
            restarted?.tokensUsed == 5,
            "a new turn must reset the displayed current-turn token count"
        )
        try expect(
            restarted?.startedAt == now.addingTimeInterval(-60),
            "the displayed start time must match the current turn"
        )

        try appendEvent(
            event(
                at: childCreatedAt.addingTimeInterval(5),
                type: "token_count",
                total: 340,
                last: 40
            ),
            to: childPath
        )
        let second = provider.read()
        let updatedChild = second.activeTasks.first { $0.id == childID }
        try expect(
            second.todayTokens == 325,
            "incremental scan should add exactly 40 tokens"
        )
        try expect(
            updatedChild?.tokensUsed == 140,
            "current-turn tokens should update incrementally"
        )

        try appendEvent(
            event(
                at: childCreatedAt.addingTimeInterval(6),
                type: "token_count",
                total: 20,
                last: 5
            ),
            to: childPath
        )
        let afterReset = provider.read()
        let resetChild = afterReset.activeTasks.first { $0.id == childID }
        try expect(
            afterReset.todayTokens == 330,
            "a cumulative reset should count last usage once, not drop or replay history"
        )
        try expect(
            resetChild?.tokensUsed == 145,
            "current-turn tokens should include usage across a cumulative reset"
        )
    }

    private static func testRecentCountHasNoRowLimit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let now = try date("2026-07-27T08:30:00.000Z")
        for index in 0..<161 {
            try fixture.insertThread(
                id: "recent-\(index)",
                path: fixture.rolloutPath("missing-\(index)"),
                createdAt: now,
                updatedAt: now,
                title: "Recent \(index)"
            )
        }
        fixture.closeDatabase()

        let provider = LocalDataProvider(
            databasePath: fixture.databasePath,
            now: { now }
        )
        let metrics = provider.read()
        try expect(
            metrics.recentTaskCount == 161,
            "recent count must not be capped at 160"
        )
    }

    private static func testLegacyWidgetSnapshotCompatibility() throws {
        let legacy: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": "2026-07-27T08:00:00Z",
            "hasCredits": false,
            "unlimitedCredits": false,
            "todayCreatedTaskTokens": 12,
            "activeTasks": [],
            "recentTaskCount": 3,
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshotV1.self, from: data)
        try expect(
            decoded.effectiveActiveTaskCount == 0,
            "a v1 snapshot without the new count must still decode"
        )
        try expect(
            decoded.accountUsageThroughDate == nil,
            "a v1 snapshot must default the cutoff date to nil"
        )
    }

    private static func event(
        at timestamp: Date,
        type: String,
        startedAt: Date? = nil,
        turnID: String? = nil,
        total: Int64? = nil,
        last: Int64? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = ["type": type]
        if let startedAt {
            payload["started_at"] = Int64(startedAt.timeIntervalSince1970)
        }
        if let turnID {
            payload["turn_id"] = turnID
        }
        if let total {
            payload["info"] = [
                "total_token_usage": ["total_tokens": total],
                "last_token_usage": ["total_tokens": last ?? total],
            ]
        }
        return [
            "timestamp": iso8601.string(from: timestamp),
            "type": "event_msg",
            "payload": payload,
        ]
    }

    private static func sessionMeta(forkedFromID: String) -> [String: Any] {
        [
            "timestamp": iso8601.string(from: Date()),
            "type": "session_meta",
            "payload": [
                "forked_from_id": forkedFromID,
            ],
        ]
    }

    private static func uuidV7(at date: Date, suffix: String) -> String {
        let milliseconds = UInt64(date.timeIntervalSince1970 * 1_000)
        let prefix = String(format: "%012llx", milliseconds)
        return "\(prefix.prefix(8))-\(prefix.suffix(4))-7000-8000-\(suffix)"
    }

    private static func writeEvents(
        _ events: [[String: Any]],
        to path: String
    ) throws {
        var data = Data()
        for event in events {
            data.append(try JSONSerialization.data(withJSONObject: event))
            data.append(0x0A)
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func appendEvent(
        _ event: [String: Any],
        to path: String
    ) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONSerialization.data(withJSONObject: event)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func date(_ value: String) throws -> Date {
        guard let date = iso8601.date(from: value) else {
            throw TestFailure("invalid test date \(value)")
        }
        return date
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

private final class Fixture {
    let directory: URL
    let databasePath: String
    private var database: OpaquePointer?

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-pulse-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        databasePath = directory
            .appendingPathComponent("state_5.sqlite")
            .path

        guard sqlite3_open(databasePath, &database) == SQLITE_OK else {
            throw TestFailure("could not create fixture database")
        }
        try execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                title TEXT NOT NULL,
                preview TEXT NOT NULL DEFAULT '',
                agent_nickname TEXT,
                agent_path TEXT,
                model TEXT,
                source TEXT NOT NULL DEFAULT 'test',
                cli_version TEXT NOT NULL DEFAULT 'test',
                archived INTEGER NOT NULL DEFAULT 0
            )
            """
        )
    }

    func rolloutPath(_ name: String) -> String {
        directory.appendingPathComponent("\(name).jsonl").path
    }

    func insertThread(
        id: String,
        path: String,
        createdAt: Date,
        updatedAt: Date,
        title: String,
        agentPath: String? = nil
    ) throws {
        guard let database else {
            throw TestFailure("fixture database is closed")
        }
        let sql = """
        INSERT INTO threads (
            id, rollout_path, created_at, updated_at, title, preview,
            agent_nickname, agent_path, model, source, cli_version, archived
        ) VALUES (?1, ?2, ?3, ?4, ?5, '', NULL, ?6, 'test-model', ?7, 'test', 0)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw TestFailure("could not prepare fixture insert")
        }
        defer { sqlite3_finalize(statement) }

        bind(id, to: 1, in: statement)
        bind(path, to: 2, in: statement)
        sqlite3_bind_int64(
            statement,
            3,
            Int64(createdAt.timeIntervalSince1970)
        )
        sqlite3_bind_int64(
            statement,
            4,
            Int64(updatedAt.timeIntervalSince1970)
        )
        bind(title, to: 5, in: statement)
        bind(agentPath, to: 6, in: statement)
        bind(agentPath == nil ? "test" : #"{"subagent":{}}"#, to: 7, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TestFailure("could not insert fixture thread")
        }
    }

    func closeDatabase() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    func remove() {
        closeDatabase()
        try? FileManager.default.removeItem(at: directory)
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw TestFailure("fixture database is closed")
        }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestFailure("could not initialize fixture database")
        }
    }

    private func bind(
        _ value: String?,
        to index: Int32,
        in statement: OpaquePointer
    ) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
