import AppKit
import SwiftUI

@main
struct PadMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.bootstrap()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var isHiddenToTray = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureStatusItem()
        observeWindowCommands()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.forEach { window in
                window.appearance = NSAppearance(named: .aqua)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    @objc private func showMainWindow() {
        isHiddenToTray = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.forEach { window in
                window.appearance = NSAppearance(named: .aqua)
                window.makeKeyAndOrderFront(nil)
            }
        }
        rebuildStatusMenu()
    }

    @objc private func hideToTray() {
        isHiddenToTray = true
        NSApp.windows.forEach { window in
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
        rebuildStatusMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "PadMapper")
            button.imagePosition = .imageLeading
            button.toolTip = "PadMapper"
        }
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(
            withTitle: isHiddenToTray ? "显示主窗口" : "隐藏到托盘",
            action: isHiddenToTray ? #selector(showMainWindow) : #selector(hideToTray),
            keyEquivalent: ""
        )
        if !isHiddenToTray {
            menu.addItem(withTitle: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 PadMapper", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func observeWindowCommands() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideToTray),
            name: .padMapperHideToTrayRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainWindow),
            name: .padMapperShowMainWindowRequested,
            object: nil
        )
    }
}

extension Notification.Name {
    static let padMapperHideToTrayRequested = Notification.Name("PadMapperHideToTrayRequested")
    static let padMapperShowMainWindowRequested = Notification.Name("PadMapperShowMainWindowRequested")
}
