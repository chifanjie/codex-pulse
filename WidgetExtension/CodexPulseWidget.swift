import SwiftUI
import WidgetKit
#if PROMO_RENDER
import AppKit
#endif

private enum CodexWidgetMode: String {
    case overview
    case quota
    case tokens
    case tasks
}

private struct CodexWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshotV1
}

private struct CodexTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexWidgetEntry {
        CodexWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (CodexWidgetEntry) -> Void
    ) {
        let snapshot = context.isPreview
            ? WidgetSnapshotV1.preview
            : WidgetSnapshotFile.load() ?? .unavailable
        completion(CodexWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CodexWidgetEntry>) -> Void
    ) {
        let snapshot = WidgetSnapshotFile.load() ?? .unavailable
        let entry = CodexWidgetEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct CodexWidgetView: View {
    let entry: CodexWidgetEntry
    let mode: CodexWidgetMode

    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshotV1 { entry.snapshot }
    private var accent: Color { .green }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallContent
        case .systemMedium:
            mediumContent
        default:
            largeContent
        }
    }

    @ViewBuilder
    private var smallContent: some View {
        switch mode {
        case .tokens:
            SmallTokensView(snapshot: snapshot, accent: accent)
        default:
            SmallQuotaView(snapshot: snapshot, accent: accent)
        }
    }

    @ViewBuilder
    private var mediumContent: some View {
        switch mode {
        case .overview:
            MediumOverviewView(snapshot: snapshot, accent: accent)
        case .quota:
            MediumQuotaView(snapshot: snapshot, accent: accent)
        case .tokens:
            MediumTokensView(snapshot: snapshot, accent: accent)
        case .tasks:
            TaskListView(snapshot: snapshot, accent: accent, rowLimit: 2)
        }
    }

    @ViewBuilder
    private var largeContent: some View {
        switch mode {
        case .overview:
            LargeOverviewView(snapshot: snapshot, accent: accent)
        case .quota:
            LargeQuotaView(snapshot: snapshot, accent: accent)
        case .tokens:
            LargeTokensView(snapshot: snapshot, accent: accent)
        case .tasks:
            TaskListView(snapshot: snapshot, accent: accent, rowLimit: 5)
        }
    }
}

private struct WidgetHeader: View {
    let snapshot: WidgetSnapshotV1
    var trailingText: String?
    let accent: Color
    var showsPlan = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .widgetAccentable()
            Text("Codex")
                .font(.caption.weight(.semibold))
            if showsPlan, let plan = snapshot.planType, !plan.isEmpty {
                Text(plan.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let trailingText {
                Text(trailingText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct QuotaGauge: View {
    let remainingPercent: Int?
    let accent: Color
    var diameter: CGFloat = 72

    var body: some View {
        Gauge(
            value: Double(remainingPercent ?? 0),
            in: 0...100
        ) {
            Text("额度")
        } currentValueLabel: {
            Text(remainingPercent.map { "\($0)%" } ?? "—")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(remainingPercent == nil ? Color.secondary : accent)
        .frame(width: diameter, height: diameter)
        .widgetAccentable()
        .accessibilityLabel(
            remainingPercent.map { "额度剩余 \($0)%" } ?? "额度暂不可用"
        )
    }
}

private struct SmallQuotaView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: activeLabel,
                accent: accent,
                showsPlan: false
            )

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                QuotaGauge(
                    remainingPercent: snapshot.primaryRemainingPercent,
                    accent: accent,
                    diameter: 78
                )
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                if let reset = snapshot.primaryResetsAt {
                    Text(reset, style: .relative)
                } else {
                    Text("重置时间未知")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var activeLabel: String {
        snapshot.activeTasks.isEmpty
            ? "空闲"
            : "\(snapshot.activeTasks.count) 运行中"
    }
}

private struct SmallTokensView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: nil,
                accent: accent,
                showsPlan: false
            )
            Spacer(minLength: 2)
            Text(WidgetNumber.compact(snapshot.lifetimeTokens))
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.62)
                .lineLimit(1)
                .foregroundStyle(.primary)
            Text("累计 Token Activity")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("今日创建")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(WidgetNumber.compact(snapshot.todayCreatedTaskTokens))
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(accent)
                    .widgetAccentable()
            }
        }
    }
}

private struct MediumOverviewView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: snapshot.modelName,
                accent: accent
            )

            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    QuotaGauge(
                        remainingPercent: snapshot.primaryRemainingPercent,
                        accent: accent,
                        diameter: 56
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("额度剩余")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let reset = snapshot.primaryResetsAt {
                            Text(reset, style: .relative)
                                .font(.caption.weight(.semibold))
                        } else {
                            Text("等待数据")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snapshot.activeTasks.count)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(snapshot.activeTasks.isEmpty ? "当前空闲" : "任务运行中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 10) {
                MetricCell(
                    title: "今日创建",
                    value: WidgetNumber.compact(snapshot.todayCreatedTaskTokens)
                )
                MetricCell(
                    title: "累计",
                    value: WidgetNumber.compact(snapshot.lifetimeTokens)
                )
                MetricCell(
                    title: "峰值单日",
                    value: WidgetNumber.compact(snapshot.peakDailyTokens)
                )
            }
        }
    }
}

private struct MediumQuotaView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: creditsText,
                accent: accent
            )

            HStack(spacing: 16) {
                QuotaGauge(
                    remainingPercent: snapshot.primaryRemainingPercent,
                    accent: accent,
                    diameter: 66
                )

                VStack(alignment: .leading, spacing: 7) {
                    Label("主要额度窗口", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.caption.weight(.semibold))
                    if let reset = snapshot.primaryResetsAt {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(reset, style: .relative)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    if let secondary = snapshot.secondaryRemainingPercent {
                        Label("次级窗口剩余 \(secondary)%", systemImage: "circle.dashed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    StatusLine(snapshot: snapshot)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var creditsText: String {
        if snapshot.unlimitedCredits { return "Credits 无限" }
        if snapshot.hasCredits, let balance = snapshot.creditBalance {
            return "Credits \(balance)"
        }
        return "套餐内"
    }
}

private struct MediumTokensView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: "Token Activity",
                accent: accent
            )

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                MetricCell(
                    title: "今日创建任务",
                    value: WidgetNumber.compact(snapshot.todayCreatedTaskTokens),
                    prominent: true
                )
                Divider()
                MetricCell(
                    title: "账户累计",
                    value: WidgetNumber.compact(snapshot.lifetimeTokens),
                    prominent: true
                )
                Divider()
                MetricCell(
                    title: "峰值单日",
                    value: WidgetNumber.compact(snapshot.peakDailyTokens),
                    prominent: true
                )
            }

            Spacer(minLength: 0)
            StatusLine(snapshot: snapshot)
        }
    }
}

private struct LargeOverviewView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(spacing: 11) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: snapshot.modelName,
                accent: accent
            )

            HStack(spacing: 18) {
                QuotaGauge(
                    remainingPercent: snapshot.primaryRemainingPercent,
                    accent: accent,
                    diameter: 82
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("主要额度窗口")
                        .font(.headline)
                    if let reset = snapshot.primaryResetsAt {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(reset, style: .relative)
                            Text("后重置")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    StatusLine(snapshot: snapshot)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snapshot.activeTasks.count)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(snapshot.activeTasks.isEmpty ? "当前空闲" : "任务运行中")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 12) {
                MetricCell(
                    title: "今日创建任务",
                    value: WidgetNumber.compact(snapshot.todayCreatedTaskTokens),
                    prominent: true
                )
                MetricCell(
                    title: "账户累计",
                    value: WidgetNumber.compact(snapshot.lifetimeTokens),
                    prominent: true
                )
                MetricCell(
                    title: "峰值单日",
                    value: WidgetNumber.compact(snapshot.peakDailyTokens),
                    prominent: true
                )
            }

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text("最近运行")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("本地推断")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if snapshot.activeTasks.isEmpty {
                    EmptyTasksView()
                } else {
                    ForEach(snapshot.activeTasks.prefix(3), id: \.id) { task in
                        CompactTaskRow(task: task, accent: accent)
                    }
                }
            }
        }
    }
}

private struct LargeQuotaView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(spacing: 13) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: "额度与重置",
                accent: accent
            )

            HStack(spacing: 28) {
                VStack(spacing: 7) {
                    QuotaGauge(
                        remainingPercent: snapshot.primaryRemainingPercent,
                        accent: accent,
                        diameter: 92
                    )
                    Text("主要窗口")
                        .font(.caption.weight(.semibold))
                }

                if snapshot.secondaryUsedPercent != nil {
                    VStack(spacing: 7) {
                        QuotaGauge(
                            remainingPercent: snapshot.secondaryRemainingPercent,
                            accent: .cyan,
                            diameter: 92
                        )
                        Text("次级窗口")
                            .font(.caption.weight(.semibold))
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    ResetDetail(
                        title: "主要窗口重置",
                        date: snapshot.primaryResetsAt
                    )
                    if snapshot.secondaryUsedPercent != nil {
                        ResetDetail(
                            title: "次级窗口重置",
                            date: snapshot.secondaryResetsAt
                        )
                    }
                    Label(creditsText, systemImage: "creditcard.fill")
                        .font(.caption.weight(.medium))
                }
            }

            Divider()
            Text("额度百分比表示当前时间窗口的剩余比例，不是固定 Token 数。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            StatusLine(snapshot: snapshot)
        }
    }

    private var creditsText: String {
        if snapshot.unlimitedCredits { return "Credits：无限" }
        if snapshot.hasCredits, let balance = snapshot.creditBalance {
            return "Credits：\(balance)"
        }
        return "Credits：套餐内"
    }
}

private struct LargeTokensView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: "统计可能延迟",
                accent: accent
            )

            Text(WidgetNumber.compact(snapshot.lifetimeTokens))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text("账户累计 Token Activity")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 12) {
                MetricCell(
                    title: "今日创建任务累计",
                    value: WidgetNumber.compact(snapshot.todayCreatedTaskTokens),
                    prominent: true
                )
                MetricCell(
                    title: "峰值单日",
                    value: WidgetNumber.compact(snapshot.peakDailyTokens),
                    prominent: true
                )
                MetricCell(
                    title: "近 7 天任务",
                    value: "\(snapshot.recentTaskCount)",
                    prominent: true
                )
            }

            Spacer()
            StatusLine(snapshot: snapshot)
        }
    }
}

private struct TaskListView: View {
    let snapshot: WidgetSnapshotV1
    let accent: Color
    let rowLimit: Int

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(
                snapshot: snapshot,
                trailingText: "本地推断",
                accent: accent
            )

            HStack(alignment: .firstTextBaseline) {
                Text("\(snapshot.activeTasks.count)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(snapshot.activeTasks.isEmpty ? "当前空闲" : "个任务运行中")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("近 7 天 \(snapshot.recentTaskCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if snapshot.activeTasks.isEmpty {
                EmptyTasksView()
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.activeTasks.prefix(rowLimit), id: \.id) { task in
                        CompactTaskRow(task: task, accent: accent)
                    }
                }
            }

            Spacer(minLength: 0)
            StatusLine(snapshot: snapshot)
        }
    }
}

private struct MetricCell: View {
    let title: String
    let value: String
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(
                    prominent
                        ? .system(.title3, design: .rounded, weight: .semibold)
                        : .system(.caption, design: .rounded, weight: .semibold)
                )
                .minimumScaleFactor(0.66)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactTaskRow: View {
    let task: WidgetTaskSnapshot
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .privacySensitive()
                HStack(spacing: 4) {
                    Text(task.agent)
                    if let model = task.model, !model.isEmpty {
                        Text("·")
                        Text(model)
                    }
                    Text("·")
                    Text(task.startedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(WidgetNumber.compact(task.tokensUsed))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 5)
    }
}

private struct EmptyTasksView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("当前没有运行任务")
                .font(.caption.weight(.medium))
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

private struct StatusLine: View {
    let snapshot: WidgetSnapshotV1

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var iconName: String {
        snapshot.error == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    }

    private var text: String {
        if let error = snapshot.error {
            return error
        }
        if Date().timeIntervalSince(snapshot.generatedAt) > 30 * 60 {
            return "数据可能已过期"
        }
        return "本地只读 · 已更新"
    }
}

private struct ResetDetail: View {
    let title: String
    let date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let date {
                Text(date, style: .relative)
                    .font(.headline)
            } else {
                Text("暂不可用")
                    .font(.headline)
            }
        }
    }
}

private enum WidgetNumber {
    static func compact(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return value.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
    }

    static func compact(_ value: Int64) -> String {
        compact(Optional(value))
    }
}

private struct CodexOverviewWidget: Widget {
    let kind = "com.local.codex-pulse.overview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexTimelineProvider()) { entry in
            CodexWidgetView(entry: entry, mode: .overview)
        }
        .configurationDisplayName("Codex 总览")
        .description("额度、Token 和运行任务的简洁总览。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CodexQuotaWidget: Widget {
    let kind = "com.local.codex-pulse.quota"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexTimelineProvider()) { entry in
            CodexWidgetView(entry: entry, mode: .quota)
        }
        .configurationDisplayName("Codex 额度")
        .description("查看额度剩余比例与重置时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CodexTokensWidget: Widget {
    let kind = "com.local.codex-pulse.tokens"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexTimelineProvider()) { entry in
            CodexWidgetView(entry: entry, mode: .tokens)
        }
        .configurationDisplayName("Codex Token")
        .description("查看今日创建任务、累计与峰值 Token activity。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CodexTasksWidget: Widget {
    let kind = "com.local.codex-pulse.tasks"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexTimelineProvider()) { entry in
            CodexWidgetView(entry: entry, mode: .tasks)
        }
        .configurationDisplayName("Codex 任务")
        .description("查看本机推断的运行任务与 Token。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#if PROMO_RENDER
private struct PromoChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.white.opacity(0.09))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.13), lineWidth: 1)
                    )
            )
    }
}

private struct PromoWidgetShell<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: Content

    init(
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.105, green: 0.115, blue: 0.145))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.11), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 28, y: 18)
    }
}

private struct ReadmeHeroCanvas: View {
    let snapshot: WidgetSnapshotV1
    let appIcon: NSImage

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.055, blue: 0.115),
                    Color(red: 0.035, green: 0.110, blue: 0.145),
                    Color(red: 0.020, green: 0.080, blue: 0.105),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.20, green: 0.95, blue: 0.68).opacity(0.26),
                    .clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 360
            )
            .frame(width: 720, height: 720)
            .offset(x: 410, y: -240)

            RadialGradient(
                colors: [
                    Color(red: 0.08, green: 0.70, blue: 0.98).opacity(0.18),
                    .clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 280
            )
            .frame(width: 560, height: 560)
            .offset(x: -420, y: 300)

            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

                        Text("Codex Pulse")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text("Know what’s left.\nSee what’s running.\nStay in flow.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                        .padding(.top, 34)

                    Text("Quota, tokens, and active tasks —\nright on your Mac desktop.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineSpacing(5)
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            PromoChip(
                                title: "Native WidgetKit",
                                systemImage: "macwindow"
                            )
                            PromoChip(
                                title: "Local only",
                                systemImage: "lock.fill"
                            )
                        }
                        HStack(spacing: 10) {
                            PromoChip(
                                title: "No telemetry",
                                systemImage: "shield.checkered"
                            )
                            PromoChip(
                                title: "macOS 14+",
                                systemImage: "apple.logo"
                            )
                        }
                    }
                    .padding(.top, 34)
                }
                .frame(width: 345, alignment: .leading)

                ZStack {
                    PromoWidgetShell(width: 476, height: 216) {
                        MediumOverviewView(snapshot: snapshot, accent: .green)
                    }
                    .rotationEffect(.degrees(-1.2))
                    .offset(x: -64, y: -126)

                    PromoWidgetShell(width: 206, height: 206) {
                        SmallTokensView(snapshot: snapshot, accent: .green)
                    }
                    .rotationEffect(.degrees(-2.0))
                    .offset(x: -206, y: 128)

                    PromoWidgetShell(width: 472, height: 218) {
                        TaskListView(
                            snapshot: snapshot,
                            accent: .green,
                            rowLimit: 2
                        )
                    }
                    .rotationEffect(.degrees(1.3))
                    .offset(x: 142, y: 118)
                }
                .frame(width: 747, height: 520)
            }
            .padding(.horizontal, 40)
        }
        .frame(width: 1200, height: 600)
        .environment(\.colorScheme, .dark)
    }
}

@main
struct ReadmeHeroRenderer {
    @MainActor
    static func main() throws {
        let outputPath = CommandLine.arguments.dropFirst().first
            ?? "Assets/codex-pulse-hero.png"
        let appIconPath = "Resources/AppIcon-1024.png"

        guard let appIcon = NSImage(contentsOfFile: appIconPath) else {
            throw NSError(
                domain: "CodexPulse.ReadmeHero",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not load \(appIconPath). Run from the repository root.",
                ]
            )
        }

        let now = Date()
        let snapshot = WidgetSnapshotV1(
            generatedAt: now,
            planType: "demo",
            primaryUsedPercent: 38,
            primaryResetsAt: now.addingTimeInterval(5.2 * 24 * 60 * 60),
            secondaryUsedPercent: 24,
            secondaryResetsAt: now.addingTimeInterval(12.5 * 24 * 60 * 60),
            hasCredits: false,
            unlimitedCredits: false,
            creditBalance: nil,
            todayCreatedTaskTokens: 8_400_000,
            lifetimeTokens: 2_460_000_000,
            peakDailyTokens: 312_000_000,
            activeTasks: [
                WidgetTaskSnapshot(
                    id: "demo-index",
                    title: "索引示例工作区",
                    agent: "演示任务",
                    model: "Codex",
                    tokensUsed: 860_000,
                    startedAt: now.addingTimeInterval(-12 * 60),
                    updatedAt: now
                ),
                WidgetTaskSnapshot(
                    id: "demo-tests",
                    title: "运行演示测试",
                    agent: "演示任务",
                    model: "Codex",
                    tokensUsed: 248_000,
                    startedAt: now.addingTimeInterval(-4 * 60),
                    updatedAt: now
                ),
            ],
            recentTaskCount: 18,
            modelName: "Codex",
            codexVersion: "demo",
            error: nil
        )

        let renderer = ImageRenderer(
            content: ReadmeHeroCanvas(snapshot: snapshot, appIcon: appIcon)
        )
        renderer.proposedSize = ProposedViewSize(width: 1200, height: 600)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            throw NSError(
                domain: "CodexPulse.ReadmeHero",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not render the hero image.",
                ]
            )
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(
            using: .png,
            properties: [.compressionFactor: 1]
        ) else {
            throw NSError(
                domain: "CodexPulse.ReadmeHero",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode the hero PNG.",
                ]
            )
        }

        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("Rendered \(cgImage.width)x\(cgImage.height) hero to \(outputPath)")
    }
}
#else
@main
struct CodexPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexOverviewWidget()
        CodexQuotaWidget()
        CodexTokensWidget()
        CodexTasksWidget()
    }
}
#endif
