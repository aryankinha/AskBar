//
//  FloatingWindowController.swift
//  AskBar
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let askBarStartVoiceSession = Notification.Name("askBarStartVoiceSession")
}

final class FloatingWindowController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let defaultWidth: CGFloat = 620
    private let collapsedHeight: CGFloat = 60
    private let expandedHeight: CGFloat = 480
    private let positionKey = "barPosition"
    private var isExpanded: Bool = false

    override init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 620, height: 60)
        self.panel = FloatingPanel(contentRect: initialFrame)
        self.panel.sharingType = .none
        super.init()

        let host = NSHostingView(rootView: BarView(
            onClose: { [weak self] in
                self?.hideBar()
            },
            onExpansionChange: { [weak self] expanded in
                self?.setExpanded(expanded)
            }
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        panel.delegate = self
        panel.setContentSize(NSSize(width: defaultWidth, height: collapsedHeight))
        restorePosition()
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        applyFrame(animated: true)
    }

    private func applyFrame(animated: Bool) {
        let newHeight = isExpanded ? expandedHeight : collapsedHeight
        let oldFrame = panel.frame
        // Anchor to top edge so the bar stays visually pinned where it is.
        var newOriginY = oldFrame.origin.y + (oldFrame.size.height - newHeight)
        var newOriginX = oldFrame.origin.x

        // Clamp to screen so a downward expansion never spills off the bottom
        // (or right) edge.
        if let screen = screenContaining(point: oldFrame.origin) ?? NSScreen.main {
            let visible = screen.visibleFrame
            if newOriginY < visible.minY {
                newOriginY = visible.minY + 4
            }
            if newOriginX + defaultWidth > visible.maxX {
                newOriginX = visible.maxX - defaultWidth - 4
            }
            if newOriginX < visible.minX {
                newOriginX = visible.minX + 4
            }
        }

        let newFrame = NSRect(x: newOriginX,
                              y: newOriginY,
                              width: defaultWidth,
                              height: newHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens where screen.visibleFrame.contains(point) {
            return screen
        }
        return nil
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        if let xStr = defaults.string(forKey: "\(positionKey)_x"),
           let yStr = defaults.string(forKey: "\(positionKey)_y"),
           let x = Double(xStr), let y = Double(yStr) {
            let candidate = NSPoint(x: x, y: y)
            if pointIsOnAnyScreen(candidate) {
                panel.setFrameOrigin(candidate)
                return
            }
            // Saved position is on a screen that no longer exists (e.g. an
            // external monitor that's been disconnected). Fall through to the
            // default placement so the bar isn't stranded offscreen.
        }
        placeAtDefaultPosition()
    }

    private func placeAtDefaultPosition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - defaultWidth / 2
        let y = frame.maxY - frame.height * 0.28 - collapsedHeight
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func pointIsOnAnyScreen(_ point: NSPoint) -> Bool {
        // Require a reasonable amount of the bar to be inside a screen so a
        // 1-pixel sliver doesn't count as "visible".
        let probe = NSRect(x: point.x, y: point.y, width: defaultWidth, height: collapsedHeight)
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(probe) {
                let inter = screen.visibleFrame.intersection(probe)
                if inter.width > 80 && inter.height > 20 {
                    return true
                }
            }
        }
        return false
    }

    private func savePosition() {
        let origin = panel.frame.origin
        let defaults = UserDefaults.standard
        defaults.set(String(Double(origin.x)), forKey: "\(positionKey)_x")
        defaults.set(String(Double(origin.y)), forKey: "\(positionKey)_y")
    }

    func showBar() {
        // If the display configuration changed (monitor disconnected, etc.)
        // since we last positioned the bar, recover by re-placing it.
        if !pointIsOnAnyScreen(panel.frame.origin) {
            placeAtDefaultPosition()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "\(positionKey)_x")
        UserDefaults.standard.removeObject(forKey: "\(positionKey)_y")
        placeAtDefaultPosition()
        showBar()
    }

    func startVoiceSessionFromShortcut() {
        showBar()
        NotificationCenter.default.post(name: .askBarStartVoiceSession, object: nil)
    }

    func hideBar() {
        panel.orderOut(nil)
    }

    func toggleBar() {
        if panel.isVisible {
            hideBar()
        } else {
            showBar()
        }
    }

    // MARK: - NSWindowDelegate
    func windowDidMove(_ notification: Notification) {
        savePosition()
    }
}
