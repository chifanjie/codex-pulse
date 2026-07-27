import Foundation
import WidgetKit

final class WidgetSnapshotWriter {
    private var lastSignature: WidgetSnapshotV1?
    private var lastWriteAt: Date?
    private var lastReloadAt: Date?
    private var hasPendingReload = false
    private var pendingReloadWorkItem: DispatchWorkItem?

    deinit {
        pendingReloadWorkItem?.cancel()
    }

    func publish(_ dashboard: DashboardSnapshot) {
        let now = Date()
        let error = dashboard.accountError != nil || dashboard.local.error != nil
            ? "部分数据暂不可用"
            : nil

        let widgetSnapshot = WidgetSnapshotV1(
            generatedAt: now,
            planType: dashboard.account.planType,
            primaryUsedPercent: dashboard.account.primary.usedPercent,
            primaryResetsAt: dashboard.account.primary.resetsAt,
            secondaryUsedPercent: dashboard.account.secondary?.usedPercent,
            secondaryResetsAt: dashboard.account.secondary?.resetsAt,
            hasCredits: dashboard.account.hasCredits,
            unlimitedCredits: dashboard.account.unlimitedCredits,
            creditBalance: dashboard.account.creditBalance,
            todayCreatedTaskTokens: dashboard.local.todayTokens,
            lifetimeTokens: dashboard.account.lifetimeTokens,
            peakDailyTokens: dashboard.account.peakDailyTokens,
            accountUsageThroughDate: dashboard.account.usageThroughDate,
            activeTasks: dashboard.local.activeTasks.prefix(6).map {
                WidgetTaskSnapshot(
                    id: $0.id,
                    title: $0.title,
                    agent: $0.displayAgent,
                    model: $0.model,
                    tokensUsed: $0.tokensUsed,
                    startedAt: $0.startedAt,
                    updatedAt: $0.updatedAt
                )
            },
            activeTaskCount: dashboard.local.activeTasks.count,
            recentTaskCount: dashboard.local.recentTaskCount,
            modelName: dashboard.local.modelName,
            codexVersion: dashboard.local.codexVersion,
            error: error
        )

        var signature = widgetSnapshot
        signature.generatedAt = Date(timeIntervalSince1970: 0)
        let changed = signature != lastSignature
        let heartbeatDue = lastWriteAt.map {
            now.timeIntervalSince($0) >= 15 * 60
        } ?? true

        if changed || heartbeatDue {
            do {
                let directory = WidgetSnapshotFile.url.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try WidgetSnapshotFile.encoded(widgetSnapshot).write(
                    to: WidgetSnapshotFile.url,
                    options: .atomic
                )
                lastSignature = signature
                lastWriteAt = now
                hasPendingReload = true
            } catch {
                return
            }
        }

        requestTimelineReload(at: now)
    }

    private func requestTimelineReload(at now: Date) {
        guard hasPendingReload else { return }
        let minimumInterval: TimeInterval = 15
        let elapsed = lastReloadAt.map { now.timeIntervalSince($0) }
            ?? minimumInterval

        if elapsed >= minimumInterval {
            pendingReloadWorkItem?.cancel()
            pendingReloadWorkItem = nil
            performTimelineReload()
            return
        }

        guard pendingReloadWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReloadWorkItem = nil
            guard self.hasPendingReload else { return }
            self.performTimelineReload()
        }
        pendingReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (minimumInterval - elapsed),
            execute: workItem
        )
    }

    private func performTimelineReload() {
        WidgetCenter.shared.reloadAllTimelines()
        lastReloadAt = Date()
        hasPendingReload = false
    }
}
