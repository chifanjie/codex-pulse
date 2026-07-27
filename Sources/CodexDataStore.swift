import Combine
import Foundation

final class CodexDataStore: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot
    @Published private(set) var isRefreshing = false

    var onSnapshotChanged: ((DashboardSnapshot) -> Void)?

    private let localProvider = LocalDataProvider()
    private let appServerClient = AppServerClient()
    private let worker = DispatchQueue(label: "com.local.codex-usage-widget.refresh")
    private var timer: Timer?
    private var lastAccountFetch: Date?
    private var pendingForcedRefresh = false

    init() {
        let cachedAccount = Self.loadCachedAccount()
        snapshot = DashboardSnapshot(
            account: cachedAccount,
            local: LocalMetrics(),
            refreshedAt: Date(),
            accountError: nil
        )
        lastAccountFetch = cachedAccount.lastFetchedAt
    }

    func start() {
        refresh(forceAccount: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
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
        refresh(forceAccount: true)
    }

    private func refresh(forceAccount: Bool = false) {
        if isRefreshing {
            pendingForcedRefresh = pendingForcedRefresh || forceAccount
            return
        }

        isRefreshing = true
        let currentAccount = snapshot.account
        let shouldFetchAccount = forceAccount
            || lastAccountFetch == nil
            || Date().timeIntervalSince(lastAccountFetch!) >= 180

        worker.async { [weak self] in
            guard let self else { return }

            let local = self.localProvider.read()
            let accountResult = shouldFetchAccount ? self.appServerClient.query() : nil

            DispatchQueue.main.async {
                var next = self.snapshot
                if local.error == nil {
                    next.local = local
                } else {
                    next.local.error = local.error
                }
                next.refreshedAt = Date()

                if let accountResult {
                    next.account = Self.merge(
                        fresh: accountResult.metrics,
                        fallback: currentAccount
                    )
                    next.accountError = accountResult.error
                    self.lastAccountFetch = Date()
                    Self.saveCachedAccount(next.account)
                }

                self.snapshot = next
                self.isRefreshing = false
                self.onSnapshotChanged?(next)

                if self.pendingForcedRefresh {
                    self.pendingForcedRefresh = false
                    self.refresh(forceAccount: true)
                }
            }
        }
    }

    private static func merge(
        fresh: AccountMetrics,
        fallback: AccountMetrics
    ) -> AccountMetrics {
        var result = fresh

        if !fresh.rateLimitsLoaded {
            result.planType = fallback.planType
            result.primary = fallback.primary
            result.secondary = fallback.secondary
            result.hasCredits = fallback.hasCredits
            result.unlimitedCredits = fallback.unlimitedCredits
            result.creditBalance = fallback.creditBalance
            result.rateLimitsLoaded = fallback.rateLimitsLoaded
        }

        if !fresh.usageLoaded {
            result.lifetimeTokens = fallback.lifetimeTokens
            result.peakDailyTokens = fallback.peakDailyTokens
            result.longestRunningTurnSeconds = fallback.longestRunningTurnSeconds
            result.usageLoaded = fallback.usageLoaded
        }

        if result.lastFetchedAt == nil {
            result.lastFetchedAt = fallback.lastFetchedAt
        }

        return result
    }

    private static func loadCachedAccount() -> AccountMetrics {
        let defaults = UserDefaults.standard
        let resetValue = defaults.double(forKey: "account.primary.resetAt")
        let secondaryResetValue = defaults.double(forKey: "account.secondary.resetAt")
        let fetchedValue = defaults.double(forKey: "account.fetchedAt")

        var account = AccountMetrics()
        account.planType = defaults.string(forKey: "account.plan")
        account.primary = UsageWindow(
            usedPercent: Self.cachedInt("account.primary.usedPercent"),
            windowDurationMinutes: Self.cachedInt("account.primary.minutes"),
            resetsAt: resetValue > 0 ? Date(timeIntervalSince1970: resetValue) : nil
        )
        account.rateLimitsLoaded = account.primary.usedPercent != nil

        if defaults.object(forKey: "account.secondary.usedPercent") != nil {
            account.secondary = UsageWindow(
                usedPercent: Self.cachedInt("account.secondary.usedPercent"),
                windowDurationMinutes: Self.cachedInt("account.secondary.minutes"),
                resetsAt: secondaryResetValue > 0
                    ? Date(timeIntervalSince1970: secondaryResetValue)
                    : nil
            )
        }

        account.hasCredits = defaults.bool(forKey: "account.hasCredits")
        account.unlimitedCredits = defaults.bool(forKey: "account.unlimitedCredits")
        account.creditBalance = defaults.string(forKey: "account.creditBalance")
        account.lifetimeTokens = Self.cachedInt64("account.lifetimeTokens")
        account.peakDailyTokens = Self.cachedInt64("account.peakDailyTokens")
        account.longestRunningTurnSeconds = Self.cachedInt64("account.longestRunningTurnSeconds")
        account.usageLoaded = account.lifetimeTokens != nil || account.peakDailyTokens != nil
        account.lastFetchedAt = fetchedValue > 0 ? Date(timeIntervalSince1970: fetchedValue) : nil
        return account
    }

    private static func saveCachedAccount(_ account: AccountMetrics) {
        let defaults = UserDefaults.standard
        defaults.set(account.planType, forKey: "account.plan")
        Self.setOptional(account.primary.usedPercent, forKey: "account.primary.usedPercent")
        defaults.set(account.primary.windowDurationMinutes, forKey: "account.primary.minutes")
        defaults.set(account.primary.resetsAt?.timeIntervalSince1970 ?? 0, forKey: "account.primary.resetAt")

        if let secondary = account.secondary {
            Self.setOptional(secondary.usedPercent, forKey: "account.secondary.usedPercent")
            defaults.set(secondary.windowDurationMinutes, forKey: "account.secondary.minutes")
            defaults.set(secondary.resetsAt?.timeIntervalSince1970 ?? 0, forKey: "account.secondary.resetAt")
        } else {
            defaults.removeObject(forKey: "account.secondary.usedPercent")
            defaults.removeObject(forKey: "account.secondary.minutes")
            defaults.removeObject(forKey: "account.secondary.resetAt")
        }

        defaults.set(account.hasCredits, forKey: "account.hasCredits")
        defaults.set(account.unlimitedCredits, forKey: "account.unlimitedCredits")
        defaults.set(account.creditBalance, forKey: "account.creditBalance")
        defaults.set(account.lifetimeTokens, forKey: "account.lifetimeTokens")
        defaults.set(account.peakDailyTokens, forKey: "account.peakDailyTokens")
        defaults.set(
            account.longestRunningTurnSeconds,
            forKey: "account.longestRunningTurnSeconds"
        )
        defaults.set(account.lastFetchedAt?.timeIntervalSince1970 ?? 0, forKey: "account.fetchedAt")
    }

    private static func cachedInt(_ key: String) -> Int? {
        guard let number = UserDefaults.standard.object(forKey: key) as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private static func cachedInt64(_ key: String) -> Int64? {
        guard let number = UserDefaults.standard.object(forKey: key) as? NSNumber else {
            return nil
        }
        return number.int64Value
    }

    private static func setOptional<T>(_ value: T?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
