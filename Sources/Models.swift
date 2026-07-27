import Foundation

struct UsageWindow: Equatable {
    var usedPercent: Int?
    var windowDurationMinutes: Int?
    var resetsAt: Date?

    var remainingPercent: Int? {
        usedPercent.map { max(0, min(100, 100 - $0)) }
    }
}

struct AccountMetrics: Equatable {
    var planType: String?
    var primary = UsageWindow()
    var secondary: UsageWindow?
    var hasCredits = false
    var unlimitedCredits = false
    var creditBalance: String?
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSeconds: Int64?
    var usageThroughDate: String?
    var lastFetchedAt: Date?
    var rateLimitsFetchedAt: Date?
    var usageFetchedAt: Date?
    var rateLimitsLoaded = false
    var usageLoaded = false
}

struct ActiveTask: Identifiable, Equatable {
    let id: String
    let title: String
    let agentName: String?
    let model: String?
    let tokensUsed: Int64
    let startedAt: Date
    let updatedAt: Date
    let isSubagent: Bool

    var displayAgent: String {
        if let agentName, !agentName.isEmpty {
            return agentName
        }
        return isSubagent ? "子任务" : "主任务"
    }
}

struct LocalMetrics: Equatable {
    var todayTokens: Int64 = 0
    var activeTasks: [ActiveTask] = []
    var recentTaskCount: Int = 0
    var modelName: String?
    var codexVersion: String?
    var error: String?
}

struct DashboardSnapshot: Equatable {
    var account = AccountMetrics()
    var local = LocalMetrics()
    var refreshedAt = Date()
    var accountError: String?

    static let empty = DashboardSnapshot()
}

enum NumberFormatters {
    static func compact(_ value: Int64?) -> String {
        guard let value else { return "—" }

        let amount = Double(value)
        let absolute = abs(amount)
        let suffix: String
        let divisor: Double

        switch absolute {
        case 1_000_000_000...:
            suffix = "B"
            divisor = 1_000_000_000
        case 1_000_000...:
            suffix = "M"
            divisor = 1_000_000
        case 1_000...:
            suffix = "K"
            divisor = 1_000
        default:
            return NumberFormatter.grouped.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        let scaled = amount / divisor
        let digits = absolute >= divisor * 100 ? 0 : (absolute >= divisor * 10 ? 1 : 2)
        return "\(scaled.formatted(.number.precision(.fractionLength(digits))))\(suffix)"
    }

    static func grouped(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.grouped.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(until date: Date?) -> String {
        guard let date else { return "—" }
        let interval = max(0, date.timeIntervalSinceNow)

        if interval < 60 {
            return "即将重置"
        }

        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)天 \(hours)小时"
        }
        if hours > 0 {
            return "\(hours)小时 \(minutes)分"
        }
        return "\(minutes)分钟"
    }

    static func elapsed(since date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        if minutes > 0 {
            return "\(minutes)分钟"
        }
        return "刚刚"
    }
}

private extension NumberFormatter {
    static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
