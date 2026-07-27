import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = CodexDataStore()
    private let widgetSnapshotWriter = WidgetSnapshotWriter()
    private var statusItem: NSStatusItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createStatusItem()

        store.onSnapshotChanged = { [weak self] snapshot in
            self?.updateStatusItem(for: snapshot)
            self?.widgetSnapshotWriter.publish(snapshot)
        }
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: "Codex 用量"
            )
            button.image?.isTemplate = true
            button.toolTip = "Codex Pulse"
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "Codex Pulse", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let addWidgetItem = NSMenuItem(
            title: "添加原生桌面小组件…",
            action: #selector(showNativeWidgetInstructions),
            keyEquivalent: ""
        )
        addWidgetItem.target = self
        menu.addItem(addWidgetItem)

        let refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openCodexItem = NSMenuItem(
            title: "打开 Codex",
            action: #selector(openCodex),
            keyEquivalent: ""
        )
        openCodexItem.target = self
        menu.addItem(openCodexItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(
            title: "登录时启动",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 Codex Pulse",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuState()
    }

    private func updateStatusItem(for snapshot: DashboardSnapshot) {
        let count = snapshot.local.activeTasks.count
        statusItem.button?.toolTip = count == 0
            ? "Codex Pulse · 当前空闲"
            : "Codex Pulse · \(count) 个任务运行中"
    }

    private func updateMenuState() {
        guard statusItem != nil else { return }

        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                loginItem?.state = .on
                loginItem?.toolTip = nil
            case .requiresApproval:
                loginItem?.state = .mixed
                loginItem?.toolTip = "需要在“系统设置 → 登录项”中批准"
            default:
                loginItem?.state = .off
                loginItem?.toolTip = nil
            }
        } else {
            loginItem?.isEnabled = false
        }
    }

    @objc private func refresh() {
        store.manualRefresh()
    }

    @objc private func showNativeWidgetInstructions() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "添加 Codex Pulse 小组件"
        alert.informativeText = """
        在桌面空白处点按右键，选择“编辑小组件…”，搜索 Codex Pulse。

        你可以选择“总览、额度、Token、任务”。总览、额度和 Token 支持小、中、大尺寸；任务支持中、大尺寸。

        位置、层级和移除方式都和其他 macOS 小组件一样，由系统统一管理。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func openCodex() {
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        NSWorkspace.shared.open(appURL)
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else { return }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            )
        }
        updateMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
