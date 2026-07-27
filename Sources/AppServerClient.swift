import Foundation
import Darwin

final class AppServerClient {
    struct QueryResult {
        let metrics: AccountMetrics
        let error: String?
    }

    private let codexExecutable: URL?

    init() {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        codexExecutable = candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    func query(timeout: TimeInterval = 12) -> QueryResult {
        guard let codexExecutable else {
            return QueryResult(metrics: AccountMetrics(), error: "未找到 Codex CLI")
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = codexExecutable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        let collector = ResponseCollector(input: inputPipe.fileHandleForWriting)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            collector.consume(data)
        }
        process.terminationHandler = { _ in
            collector.processExited()
        }

        var didStart = false
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? inputPipe.fileHandleForWriting.close()

            if didStart {
                if process.isRunning {
                    process.terminate()
                    Self.waitForExit(process, timeout: 1)
                }
                if process.isRunning {
                    Darwin.kill(pid_t(process.processIdentifier), SIGKILL)
                    Self.waitForExit(process, timeout: 0.5)
                }
                if !process.isRunning {
                    process.waitUntilExit()
                }
                process.terminationHandler = nil
            }
        }

        do {
            try process.run()
            didStart = true
            try collector.send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-usage-widget",
                        "title": "Codex Usage Widget",
                        "version": "2.0.0",
                    ],
                    "capabilities": [
                        "experimentalApi": true,
                    ],
                ],
            ])
        } catch {
            return QueryResult(metrics: AccountMetrics(), error: "无法启动 Codex 数据服务")
        }

        let waitResult = collector.wait(timeout: timeout)

        guard waitResult else {
            return QueryResult(metrics: AccountMetrics(), error: "账户用量刷新超时")
        }

        let responses = collector.responses
        var metrics = AccountMetrics()
        var errors: [String] = []

        if let rateResponse = responses[2] {
            if let message = Self.errorMessage(from: rateResponse) {
                errors.append(message)
            } else if !Self.applyRateLimits(from: rateResponse, to: &metrics) {
                errors.append("额度数据格式不兼容")
            }
        } else {
            errors.append("未收到额度数据")
        }

        if let usageResponse = responses[3] {
            if let message = Self.errorMessage(from: usageResponse) {
                errors.append(message)
            } else if !Self.applyUsage(from: usageResponse, to: &metrics) {
                errors.append("Token activity 数据格式不兼容")
            }
        } else {
            errors.append("未收到 token activity")
        }

        if metrics.rateLimitsLoaded || metrics.usageLoaded {
            metrics.lastFetchedAt = Date()
        }
        return QueryResult(
            metrics: metrics,
            error: errors.isEmpty ? nil : errors.joined(separator: "；")
        )
    }

    private static func applyRateLimits(
        from response: [String: Any],
        to metrics: inout AccountMetrics
    ) -> Bool {
        guard
            let result = response["result"] as? [String: Any],
            let snapshot = result["rateLimits"] as? [String: Any],
            let primary = parseWindow(snapshot["primary"]),
            let credits = snapshot["credits"] as? [String: Any],
            let hasCredits = credits["hasCredits"] as? Bool,
            let unlimitedCredits = credits["unlimited"] as? Bool
        else {
            return false
        }

        let secondary: UsageWindow?
        if snapshot["secondary"] is NSNull || snapshot["secondary"] == nil {
            secondary = nil
        } else {
            guard let parsedSecondary = parseWindow(snapshot["secondary"]) else {
                return false
            }
            secondary = parsedSecondary
        }

        metrics.planType = snapshot["planType"] as? String
        metrics.primary = primary
        metrics.secondary = secondary
        metrics.hasCredits = hasCredits
        metrics.unlimitedCredits = unlimitedCredits
        metrics.creditBalance = credits["balance"] as? String
        metrics.rateLimitsLoaded = true
        return true
    }

    private static func applyUsage(
        from response: [String: Any],
        to metrics: inout AccountMetrics
    ) -> Bool {
        guard
            let result = response["result"] as? [String: Any],
            let summary = result["summary"] as? [String: Any]
        else {
            return false
        }

        let lifetimeTokens = int64(summary["lifetimeTokens"])
        let peakDailyTokens = int64(summary["peakDailyTokens"])
        let longestRunningTurnSeconds = int64(summary["longestRunningTurnSec"])
        guard lifetimeTokens != nil
                || peakDailyTokens != nil
                || longestRunningTurnSeconds != nil
        else {
            return false
        }

        metrics.lifetimeTokens = lifetimeTokens
        metrics.peakDailyTokens = peakDailyTokens
        metrics.longestRunningTurnSeconds = longestRunningTurnSeconds
        metrics.usageLoaded = true
        return true
    }

    private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard
            let object = value as? [String: Any],
            let used = int(object["usedPercent"])
        else {
            return nil
        }

        let minutes = int(object["windowDurationMins"])
        let resetDate = int64(object["resetsAt"]).map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }

        return UsageWindow(
            usedPercent: max(0, min(100, used)),
            windowDurationMinutes: minutes,
            resetsAt: resetDate
        )
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
    }

    private static func errorMessage(from response: [String: Any]) -> String? {
        guard let error = response["error"] as? [String: Any] else { return nil }
        return error["message"] as? String ?? "Codex 数据接口返回错误"
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }
}

private final class ResponseCollector {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let input: FileHandle
    private var buffer = Data()
    private var storedResponses: [Int: [String: Any]] = [:]
    private var didSignal = false
    private var didSendReadRequests = false

    init(input: FileHandle) {
        self.input = input
    }

    var responses: [Int: [String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return storedResponses
    }

    func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var line = data
        line.append(0x0A)
        try input.write(contentsOf: line)
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else {
            processExited()
            return
        }

        lock.lock()
        buffer.append(data)
        let lines = drainCompleteLines()
        lock.unlock()

        for line in lines {
            guard
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let number = object["id"] as? NSNumber
            else {
                continue
            }

            let id = number.intValue
            lock.lock()
            storedResponses[id] = object
            let shouldInitialize = id == 1 && !didSendReadRequests
            if shouldInitialize {
                didSendReadRequests = true
            }
            let complete = storedResponses[2] != nil && storedResponses[3] != nil
            lock.unlock()

            if shouldInitialize {
                do {
                    try send(["method": "initialized"])
                    try send([
                        "id": 2,
                        "method": "account/rateLimits/read",
                        "params": NSNull(),
                    ])
                    try send([
                        "id": 3,
                        "method": "account/usage/read",
                        "params": NSNull(),
                    ])
                } catch {
                    signal()
                }
            }

            if complete {
                signal()
            }
        }
    }

    func processExited() {
        signal()
    }

    func wait(timeout: TimeInterval) -> Bool {
        let result = semaphore.wait(timeout: .now() + timeout)
        return result == .success && responses[2] != nil && responses[3] != nil
    }

    private func signal() {
        lock.lock()
        guard !didSignal else {
            lock.unlock()
            return
        }
        didSignal = true
        lock.unlock()
        semaphore.signal()
    }

    private func drainCompleteLines() -> [Data] {
        var lines: [Data] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(...newline)
        }

        return lines
    }
}
