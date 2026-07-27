import AppKit
import Foundation

@main
enum CodexUsageWidgetApp {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            runProbe()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    private static func runProbe() {
        let local = LocalDataProvider().read()
        let account = AppServerClient().query()
        let payload: [String: Any] = [
            "codexVersion": local.codexVersion as Any? ?? NSNull(),
            "localDataAvailable": local.error == nil,
            "rateLimitsAvailable": account.metrics.rateLimitsLoaded,
            "tokenActivityAvailable": account.metrics.usageLoaded,
            "accountError": account.error as Any? ?? NSNull(),
            "localError": local.error as Any? ?? NSNull(),
        ]

        if let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
    }
}
