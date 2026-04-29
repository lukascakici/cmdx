//
//  cmdxApp.swift
//  cmdx
//
//  Created by cmdx project on 25.03.2026.
//

import SwiftUI
import AppKit

@main
struct cmdxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Hidden Settings scene — required to satisfy the App protocol but never
        // shown. The real UI lives in AppDelegate's NSStatusItem, which avoids
        // the long-lived SwiftUI window/view hierarchy that MenuBarExtra(.window)
        // keeps resident across the app's lifetime.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "cmdx")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        EventInterceptor.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventInterceptor.shared.cleanup()
    }

    // Built lazily each time the menu opens, so nothing has to stay subscribed
    // to permission state in the background.
    func menuNeedsUpdate(_ menu: NSMenu) {
        EventInterceptor.shared.checkPermissions()
        let trusted = EventInterceptor.shared.isTrusted

        menu.removeAllItems()

        let status = NSMenuItem(
            title: trusted ? "cmdx — Active" : "cmdx — Permission Required",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        if !trusted {
            menu.addItem(.separator())
            let openSettings = NSMenuItem(
                title: "Open Accessibility Settings…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            openSettings.target = self
            menu.addItem(openSettings)

            let recheck = NSMenuItem(
                title: "Re-check Permissions",
                action: #selector(recheckPermissions),
                keyEquivalent: ""
            )
            recheck.target = self
            menu.addItem(recheck)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit cmdx",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func recheckPermissions() {
        EventInterceptor.shared.checkPermissions()
        if EventInterceptor.shared.isTrusted {
            EventInterceptor.shared.start()
        }
    }
}
