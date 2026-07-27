import Combine
import Foundation

final class CodexDataStore: ObservableObject {
    @Published private(set) var snapshot = DashboardSnapshot.empty
    @Published private(set) var isRefreshing = false

    var onSnapshotChanged: ((DashboardSnapshot) -> Void)?

    private let localProvider = LocalDataProvider()
    private let appServerClient = AppServerClient()
    private let localWorker = DispatchQueue(
        label: "com.local.codex-usage-widget.local-refresh"
    )
    private let accountWorker = DispatchQueue(
        label: "com.local.codex-usage-widget.account-refresh"
    )

    private let localRefreshInterval: TimeInterval = 5
    private let accountRefreshInterval: TimeInterval = 60

    private var timer: Timer?
    private var localRefreshInFlight = false
    private var accountRefreshInFlight = false
    private var pendingLocalRefresh = false
    private var pendingForcedAccountRefresh = false
    private var nextAccountRefreshAt: Date?
    private var accountFailureCount = 0
    private var accountKey: Int?
    private var hasCompletedInitialLocalRefresh = false
    private var hasCompletedInitialAccountRefresh = false

    func start() {
        refreshLocal()
        refreshAccount(force: true)

        timer = Timer.scheduledTimer(
            withTimeInterval: localRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refreshLocal()
            self?.refreshAccount()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func manualRefresh() {
        refreshLocal()
        refreshAccount(force: true)
    }

    private func refreshLocal() {
        if localRefreshInFlight {
            pendingLocalRefresh = true
            return
        }

        localRefreshInFlight = true
        updateRefreshingState()

        localWorker.async { [weak self] in
            guard let self else { return }
            let local = self.localProvider.read()

            DispatchQueue.main.async {
                var next = self.snapshot
                if local.error == nil {
                    next.local = local
                } else {
                    // A stale "running" task is worse than a brief unavailable state.
                    // Keep the last counters, but clear activity until SQLite is readable.
                    var fallback = next.local
                    fallback.activeTasks = []
                    fallback.error = local.error
                    next.local = fallback
                }
                next.refreshedAt = Date()

                self.hasCompletedInitialLocalRefresh = true
                self.commit(next)
                self.localRefreshInFlight = false
                self.updateRefreshingState()

                if self.pendingLocalRefresh {
                    self.pendingLocalRefresh = false
                    self.refreshLocal()
                }
            }
        }
    }

    private func refreshAccount(force: Bool = false) {
        if accountRefreshInFlight {
            pendingForcedAccountRefresh = pendingForcedAccountRefresh || force
            return
        }

        let requestDate = Date()
        if !force, let nextAccountRefreshAt, requestDate < nextAccountRefreshAt {
            return
        }

        accountRefreshInFlight = true
        updateRefreshingState()

        accountWorker.async { [weak self] in
            guard let self else { return }
            let result = self.appServerClient.query()

            DispatchQueue.main.async {
                var next = self.snapshot
                var accountMergeBase = next.account

                if result.accountIdentityLoaded,
                   let newKey = result.accountKey {
                    if let oldKey = self.accountKey, oldKey != newKey {
                        accountMergeBase = AccountMetrics()
                    }
                    self.accountKey = newKey
                } else {
                    // Without an identity response, retaining a missing domain
                    // could combine data from two accounts during a switch.
                    accountMergeBase = AccountMetrics()
                }

                next.account = Self.merging(
                    result.metrics,
                    into: accountMergeBase
                )
                next.accountError = result.error
                next.refreshedAt = Date()

                let isComplete = result.accountIdentityLoaded
                    && result.metrics.rateLimitsLoaded
                    && result.metrics.usageLoaded
                    && result.error == nil
                self.scheduleNextAccountRefresh(
                    after: result,
                    complete: isComplete
                )

                self.hasCompletedInitialAccountRefresh = true
                self.commit(next)
                self.accountRefreshInFlight = false
                self.updateRefreshingState()

                if self.pendingForcedAccountRefresh {
                    self.pendingForcedAccountRefresh = false
                    self.refreshAccount(force: true)
                }
            }
        }
    }

    private func scheduleNextAccountRefresh(
        after result: AppServerClient.QueryResult,
        complete: Bool
    ) {
        if complete {
            accountFailureCount = 0
            nextAccountRefreshAt = Date().addingTimeInterval(
                accountRefreshInterval
            )
            return
        }

        accountFailureCount += 1
        let hasPartialData = result.metrics.rateLimitsLoaded
            || result.metrics.usageLoaded
        let delay: TimeInterval
        if hasPartialData {
            delay = accountFailureCount == 1 ? 15 : 30
        } else {
            let exponent = min(accountFailureCount - 1, 4)
            delay = min(15 * pow(2, Double(exponent)), 180)
        }
        nextAccountRefreshAt = Date().addingTimeInterval(delay)
    }

    private static func merging(
        _ fresh: AccountMetrics,
        into existing: AccountMetrics
    ) -> AccountMetrics {
        var merged = existing

        if fresh.rateLimitsLoaded {
            merged.planType = fresh.planType
            merged.primary = fresh.primary
            merged.secondary = fresh.secondary
            merged.hasCredits = fresh.hasCredits
            merged.unlimitedCredits = fresh.unlimitedCredits
            merged.creditBalance = fresh.creditBalance
            merged.rateLimitsLoaded = true
            merged.rateLimitsFetchedAt = fresh.rateLimitsFetchedAt
        }

        if fresh.usageLoaded {
            merged.lifetimeTokens = fresh.lifetimeTokens
            merged.peakDailyTokens = fresh.peakDailyTokens
            merged.longestRunningTurnSeconds = fresh.longestRunningTurnSeconds
            merged.usageThroughDate = fresh.usageThroughDate
            merged.usageLoaded = true
            merged.usageFetchedAt = fresh.usageFetchedAt
        }

        merged.lastFetchedAt = [
            merged.rateLimitsFetchedAt,
            merged.usageFetchedAt,
        ].compactMap { $0 }.max()
        return merged
    }

    private func commit(_ next: DashboardSnapshot) {
        snapshot = next
        guard
            hasCompletedInitialLocalRefresh,
            hasCompletedInitialAccountRefresh
        else {
            return
        }
        onSnapshotChanged?(next)
    }

    private func updateRefreshingState() {
        isRefreshing = localRefreshInFlight || accountRefreshInFlight
    }
}
