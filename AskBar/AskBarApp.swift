//
//  AskBarApp.swift
//  AskBar
//

import SwiftUI
import AppKit

@main
struct AskBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.windows.forEach { window in
                            window.sharingType = .none
                        }
                    }
                }
        }
    }
}
