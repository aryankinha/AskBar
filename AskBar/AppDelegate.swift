//
//  AppDelegate.swift
//  AskBar
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    var floatingWindowController: FloatingWindowController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Status bar icon
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "AskBar")
                ?? NSImage(systemSymbolName: "brain", accessibilityDescription: "AskBar")
            button.image = image
        }

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let resetItem = NSMenuItem(title: "Reset Bar Position", action: #selector(resetBarPosition), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit AskBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        item.menu = menu
        self.statusItem = item

        // Floating window
        let controller = FloatingWindowController()
        self.floatingWindowController = controller
        controller.showBar()

        // Global hotkey
        print("AskBar: Please grant Accessibility permission in System Settings > Privacy & Security > Accessibility for AskBar")
        HotkeyManager.shared.register(
            toggleCallback: { [weak self] in
                self?.floatingWindowController?.toggleBar()
            },
            voiceSessionCallback: { [weak self] in
                let enabled = (UserDefaults.standard.object(forKey: "voiceSessionShortcutEnabled") as? Bool) ?? true
                guard enabled else { return }
                self?.floatingWindowController?.startVoiceSessionFromShortcut()
            }
        )
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.sharingType = .none
        window.title = "AskBar Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func resetBarPosition() {
        floatingWindowController?.resetPosition()
    }
}
