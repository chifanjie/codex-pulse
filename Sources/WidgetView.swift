import SwiftUI

struct WidgetView: View {
    @ObservedObject var store: CodexDataStore

    private let accent = Color(red: 0.37, green: 0.91, blue: 0.78)
    private let blue = Color(red: 0.36, green: 0.67, blue: 1.0)

    var body: some View {
        VStack(spacing: 14) {
            dragHandle
            header
            quotaSection
            tokenSection
            taskSection
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(width: 380)
        .background(background)
        .environment(\.colorScheme, .dark)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 38, height: 4)
            .padding(.bottom, -2)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), blue.opacity(0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "terminal.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color(red: 0.03, green: 0.10, blue: 0.14))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("CODEX PULSE")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(0.8)
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            liveBadge

            Button(action: store.manualRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.isRefreshing ? accent : .white.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("立即刷新")
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(liveBadgeColor)
                .frame(width: 7, height: 7)
                .shadow(
                    color: store.snapshot.local.activeTasks.isEmpty
                        ? .clear
                        : accent.opacity(0.8),
                    radius: 5
                )
            Text(liveBadgeText)
            .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    store.snapshot.local.activeTasks.isEmpty
                        ? liveBadgeColor.opacity(0.08)
                        : accent.opacity(0.12)
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    store.snapshot.local.activeTasks.isEmpty
                        ? liveBadgeColor.opacity(0.18)
                        : accent.opacity(0.28),
                    lineWidth: 1
                )
        )
    }

    private var quotaSection: some View {
        HStack(spacing: 17) {
            QuotaRing(
                remainingPercent: store.snapshot.account.primary.remainingPercent,
                accent: accent,
                blue: blue
            )

            VStack(spacing: 10) {
                DetailRow(
                    icon: "clock.arrow.circlepath",
                    label: windowLabel(store.snapshot.account.primary),
                    value: NumberFormatters.duration(
                        until: store.snapshot.account.primary.resetsAt
                    )
                )

                DetailRow(
                    icon: "creditcard.fill",
                    label: "Credits",
                    value: creditsLabel
                )

                if let secondary = store.snapshot.account.secondary {
                    DetailRow(
                        icon: "gauge.with.dots.needle.50percent",
                        label: "次级窗口",
                        value: secondary.remainingPercent.map { "剩余 \($0)%" } ?? "暂不可用"
                    )
                }
            }
        }
        .padding(15)
        .background(sectionBackground)
    }

    private var tokenSection: some View {
        VStack(spacing: 9) {
            HStack {
                Label("TOKEN ACTIVITY", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("账户统计可能延迟")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.75))
            }

            HStack(spacing: 9) {
                MetricCard(
                    title: "今日创建任务",
                    value: NumberFormatters.compact(store.snapshot.local.todayTokens),
                    caption: "累计 tokens",
                    tint: accent
                )
                MetricCard(
                    title: "累计 Activity",
                    value: NumberFormatters.compact(store.snapshot.account.lifetimeTokens),
                    caption: "tokens",
                    tint: blue
                )
                MetricCard(
                    title: "峰值单日",
                    value: NumberFormatters.compact(store.snapshot.account.peakDailyTokens),
                    caption: "tokens",
                    tint: Color(red: 0.78, green: 0.52, blue: 1.0)
                )
            }
        }
    }

    private var taskSection: some View {
        VStack(spacing: 9) {
            HStack {
                Label("正在运行", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("本地推断")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.09)))
                Text("近 7 天 \(store.snapshot.local.recentTaskCount) 个任务")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let localError = store.snapshot.local.error {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("任务数据暂不可用")
                            .font(.system(size: 12, weight: .semibold))
                        Text(localError)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(12)
                .background(sectionBackground)
            } else if store.snapshot.local.activeTasks.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accent.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前没有运行任务")
                            .font(.system(size: 12, weight: .semibold))
                        Text("有新任务时会自动出现在这里")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(sectionBackground)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(store.snapshot.local.activeTasks.prefix(4).enumerated()),
                        id: \.element.id
                    ) { index, task in
                        TaskRow(task: task, accent: accent)
                        if index < min(store.snapshot.local.activeTasks.count, 4) - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.07))
                                .padding(.leading, 31)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .background(sectionBackground)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: hasStatusError
                  ? "exclamationmark.triangle.fill"
                  : "checkmark.shield.fill")
                .foregroundStyle(
                    hasStatusError
                        ? Color.orange.opacity(0.9)
                        : accent.opacity(0.85)
                )
            Text(footerStatus)
                .lineLimit(1)
            Spacer()
            Text(
                store.snapshot.refreshedAt.formatted(
                    date: .omitted,
                    time: .shortened
                )
            )
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 25, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.025, green: 0.07, blue: 0.11).opacity(0.87),
                                Color(red: 0.025, green: 0.055, blue: 0.09).opacity(0.94),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                accent.opacity(0.08),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.38), radius: 22, y: 10)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            )
    }

    private var headerSubtitle: String {
        let plan = (store.snapshot.account.planType ?? "Codex").uppercased()
        let model = store.snapshot.local.modelName ?? "本地任务"
        return "\(plan)  ·  \(model)"
    }

    private var creditsLabel: String {
        if store.snapshot.account.unlimitedCredits {
            return "无限"
        }
        if store.snapshot.account.hasCredits,
           let balance = store.snapshot.account.creditBalance
        {
            return balance
        }
        return "套餐内"
    }

    private var footerStatus: String {
        if let error = store.snapshot.accountError {
            return error
        }
        if let error = store.snapshot.local.error {
            return error
        }
        if let version = store.snapshot.local.codexVersion, !version.isEmpty {
            return "本地只读 · Codex \(version)"
        }
        return "本地只读 · 官方账户数据"
    }

    private var hasStatusError: Bool {
        store.snapshot.accountError != nil || store.snapshot.local.error != nil
    }

    private var liveBadgeText: String {
        if store.snapshot.local.error != nil {
            return "数据异常"
        }
        if store.snapshot.local.activeTasks.isEmpty {
            return "空闲"
        }
        return "\(store.snapshot.local.activeTasks.count) 运行中"
    }

    private var liveBadgeColor: Color {
        if store.snapshot.local.error != nil {
            return .orange
        }
        return store.snapshot.local.activeTasks.isEmpty ? .gray : accent
    }

    private func windowLabel(_ window: UsageWindow) -> String {
        guard let minutes = window.windowDurationMinutes else {
            return "额度窗口"
        }
        if minutes % (24 * 60) == 0 {
            return "\(minutes / (24 * 60)) 天窗口"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时窗口"
        }
        return "\(minutes) 分钟窗口"
    }
}

private struct QuotaRing: View {
    let remainingPercent: Int?
    let accent: Color
    let blue: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)

            Circle()
                .trim(
                    from: 0,
                    to: CGFloat(
                        max(0.01, Double(remainingPercent ?? 0) / 100)
                    )
                )
                .stroke(
                    AngularGradient(
                        colors: [accent, blue, accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.28), radius: 6)
                .opacity(remainingPercent == nil ? 0 : 1)

            VStack(spacing: 0) {
                Text(remainingPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("额度剩余")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            remainingPercent.map { "额度剩余 \($0)%" } ?? "额度数据暂不可用"
        )
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            HStack(spacing: 4) {
                Capsule()
                    .fill(tint)
                    .frame(width: 13, height: 3)
                Text(caption)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.opacity(0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

private struct TaskRow: View {
    let task: ActiveTask
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: accent.opacity(0.8), radius: 4)
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(task.displayAgent)
                    if let model = task.model, !model.isEmpty {
                        Text("·")
                        Text(model)
                    }
                    Text("·")
                    Text(NumberFormatters.elapsed(since: task.startedAt))
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(NumberFormatters.compact(task.tokensUsed))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text("tokens")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }
}
