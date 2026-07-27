import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = CodexDataStore()
    private let widgetSnapshotWriter = WidgetSnapshotWriter()
    private var panel: DesktopPanel!
    private var statusItem: NSStatusItem!
    private var showHideItem: NSMenuItem!
    private var lockItem: NSMenuItem!
    private var floatingItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var isDetailPanelVisible: Bool {
        get { UserDefaults.standard.bool(forKey: "widget.detailPanelVisible") }
        set { UserDefaults.standard.set(newValue, forKey: "widget.detailPanelVisible") }
    }

    private var isLocked: Bool {
        get { UserDefaults.standard.bool(forKey: "widget.locked") }
        set { UserDefaults.standard.set(newValue, forKey: "widget.locked") }
    }

    private var isFloating: Bool {
        get { UserDefaults.standard.bool(forKey: "widget.floating") }
        set { UserDefaults.standard.set(newValue, forKey: "widget.floating") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createStatusItem()
        applyInteractionMode()

        store.onSnapshotChanged = { [weak self] snapshot in
            self?.updateStatusItem(for: snapshot)
            self?.widgetSnapshotWriter.publish(snapshot)
        }
        store.start()

        if isDetailPanelVisible {
            showWidget()
        } else {
            panel.orderOut(nil)
            updateMenuState()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createPanel() {
        let size = NSSize(width: 380, height: panelHeight(forActiveTaskCount: 0))
        panel = DesktopPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: WidgetView(store: store))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        let autosaveName = "CodexUsageWidget.DesktopFrame"
        let frameDefaultsKey = "NSWindow Frame \(autosaveName)"
        let hasSavedFrame = UserDefaults.standard.object(forKey: frameDefaultsKey) != nil
        if hasSavedFrame {
            _ = panel.setFrameUsingName(autosaveName)
        }
        panel.setFrameAutosaveName(autosaveName)

        if !hasSavedFrame {
            positionPanelOnDesktop(size: size)
        }
        applyWindowLevel()
    }

    private func positionPanelOnDesktop(size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: frame.maxX - size.width - 28,
            y: frame.maxY - size.height - 30
        )
        panel.setFrameOrigin(origin)
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

        showHideItem = NSMenuItem(
            title: "显示详细面板",
            action: #selector(toggleWidget),
            keyEquivalent: ""
        )
        showHideItem.target = self
        menu.addItem(showHideItem)

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

        lockItem = NSMenuItem(
            title: "锁定详细面板位置",
            action: #selector(toggleLock),
            keyEquivalent: ""
        )
        lockItem.target = self
        menu.addItem(lockItem)

        floatingItem = NSMenuItem(
            title: "详细面板始终置顶",
            action: #selector(toggleFloating),
            keyEquivalent: ""
        )
        floatingItem.target = self
        menu.addItem(floatingItem)

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

    private func applyWindowLevel() {
        if isFloating {
            panel.level = .floating
        } else {
            let desktopWidgetLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 2
            panel.level = NSWindow.Level(rawValue: desktopWidgetLevel)
        }
    }

    private func applyInteractionMode() {
        panel.ignoresMouseEvents = isLocked
        panel.isMovableByWindowBackground = !isLocked
        applyWindowLevel()
        updateMenuState()
    }

    private func updateStatusItem(for snapshot: DashboardSnapshot) {
        let count = snapshot.local.activeTasks.count
        statusItem.button?.toolTip = count == 0
            ? "Codex Pulse · 当前空闲"
            : "Codex Pulse · \(count) 个任务运行中"
        resizePanel(forActiveTaskCount: count)
    }

    private func panelHeight(forActiveTaskCount count: Int) -> CGFloat {
        420 + CGFloat(min(max(count, 0), 4) * 32)
    }

    private func resizePanel(forActiveTaskCount count: Int) {
        let targetHeight = panelHeight(forActiveTaskCount: count)
        let currentFrame = panel.frame
        guard abs(currentFrame.height - targetHeight) > 1 else { return }

        let targetFrame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetHeight,
            width: currentFrame.width,
            height: targetHeight
        )
        panel.setFrame(targetFrame, display: true, animate: true)
    }

    private func updateMenuState() {
        guard panel != nil, statusItem != nil else { return }
        showHideItem?.title = panel.isVisible ? "隐藏详细面板" : "显示详细面板"
        lockItem?.state = isLocked ? .on : .off
        floatingItem?.state = isFloating ? .on : .off

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

    private func showWidget() {
        isDetailPanelVisible = true
        panel.orderFrontRegardless()
        updateMenuState()
    }

    @objc private func toggleWidget() {
        if panel.isVisible {
            panel.orderOut(nil)
            isDetailPanelVisible = false
        } else {
            showWidget()
        }
        updateMenuState()
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

    @objc private func toggleLock() {
        isLocked.toggle()
        applyInteractionMode()
    }

    @objc private func toggleFloating() {
        isFloating.toggle()
        applyWindowLevel()
        panel.orderFrontRegardless()
        updateMenuState()
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

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "codexpulse" }) else { return }
        showWidget()
    }
}
