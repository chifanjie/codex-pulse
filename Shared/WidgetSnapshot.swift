import Foundation
import Darwin

struct WidgetTaskSnapshot: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var agent: String
    var model: String?
    var tokensUsed: Int64
    var startedAt: Date
    var updatedAt: Date
}

struct WidgetSnapshotV1: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var generatedAt: Date
    var planType: String?
    var primaryUsedPercent: Int?
    var primaryResetsAt: Date?
    var secondaryUsedPercent: Int?
    var secondaryResetsAt: Date?
    var hasCredits: Bool
    var unlimitedCredits: Bool
    var creditBalance: String?
    var todayCreatedTaskTokens: Int64
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var accountUsageThroughDate: String? = nil
    var activeTasks: [WidgetTaskSnapshot]
    var activeTaskCount: Int? = nil
    var recentTaskCount: Int
    var modelName: String?
    var codexVersion: String?
    var error: String?

    var primaryRemainingPercent: Int? {
        primaryUsedPercent.map { max(0, min(100, 100 - $0)) }
    }

    var secondaryRemainingPercent: Int? {
        secondaryUsedPercent.map { max(0, min(100, 100 - $0)) }
    }

    var effectiveActiveTaskCount: Int {
        activeTaskCount ?? activeTasks.count
    }

    static let preview = WidgetSnapshotV1(
        generatedAt: Date(),
        planType: "pro",
        primaryUsedPercent: 18,
        primaryResetsAt: Date().addingTimeInterval(6.4 * 24 * 60 * 60),
        secondaryUsedPercent: nil,
        secondaryResetsAt: nil,
        hasCredits: false,
        unlimitedCredits: false,
        creditBalance: nil,
        todayCreatedTaskTokens: 12_800_000,
        lifetimeTokens: 4_680_000_000,
        peakDailyTokens: 888_000_000,
        activeTasks: [
            WidgetTaskSnapshot(
                id: "preview-main",
                title: "优化 Codex 桌面小组件",
                agent: "主任务",
                model: "gpt-5.6-sol",
                tokensUsed: 1_860_000,
                startedAt: Date().addingTimeInterval(-14 * 60),
                updatedAt: Date()
            ),
            WidgetTaskSnapshot(
                id: "preview-agent",
                title: "验证原生 WidgetKit 布局",
                agent: "设计检查",
                model: "gpt-5.6-sol",
                tokensUsed: 428_000,
                startedAt: Date().addingTimeInterval(-4 * 60),
                updatedAt: Date()
            ),
        ],
        recentTaskCount: 42,
        modelName: "gpt-5.6-sol",
        codexVersion: "0.146",
        error: nil
    )

    static let unavailable = WidgetSnapshotV1(
        generatedAt: Date(),
        planType: nil,
        primaryUsedPercent: nil,
        primaryResetsAt: nil,
        secondaryUsedPercent: nil,
        secondaryResetsAt: nil,
        hasCredits: false,
        unlimitedCredits: false,
        creditBalance: nil,
        todayCreatedTaskTokens: 0,
        lifetimeTokens: nil,
        peakDailyTokens: nil,
        activeTasks: [],
        recentTaskCount: 0,
        modelName: nil,
        codexVersion: nil,
        error: "请先打开 Codex Pulse"
    )
}

enum WidgetSnapshotFile {
    static var url: URL {
        realHomeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Codex Pulse", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json", isDirectory: false)
    }

    private static var realHomeDirectory: URL {
        guard
            let user = getpwuid(getuid()),
            let directory = user.pointee.pw_dir
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    static func encoded(_ snapshot: WidgetSnapshotV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func load() -> WidgetSnapshotV1? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshotV1.self, from: data)
    }
}
