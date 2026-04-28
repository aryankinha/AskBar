//
//  HotkeyManager.swift
//  AskBar
//
//  Uses Carbon's RegisterEventHotKey API. Unlike CGEvent taps this:
//   - does NOT require Accessibility permission
//   - is reserved at the OS level so the keystroke is not consumed by other apps
//   - survives sleep/wake cycles and Mission Control changes
//   - never gets "disabled by timeout" the way event taps do
//

import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var toggleCallback: (() -> Void)?
    private var voiceSessionCallback: (() -> Void)?

    private var toggleHotKeyRef: EventHotKeyRef?
    private var voiceHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Distinct 4-char IDs so the global event handler knows which fired.
    private let toggleHotKeyID: UInt32 = 0x41534B31 // 'ASK1'
    private let voiceHotKeyID:  UInt32 = 0x41534B32 // 'ASK2'
    private let signature:      OSType = 0x41534B72 // 'ASKr'

    private init() {}

    func register(toggleCallback: @escaping () -> Void,
                  voiceSessionCallback: @escaping () -> Void) {
        self.toggleCallback = toggleCallback
        self.voiceSessionCallback = voiceSessionCallback

        installEventHandlerIfNeeded()
        registerHotKeys()
    }

    // MARK: - Setup

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef = eventRef, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr else { return err }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKey(id: hkID.id)
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandlerRef
        )

        if status != noErr {
            print("AskBar: InstallEventHandler failed (status=\(status))")
        }
    }

    private func registerHotKeys() {
        // ⌘⇧Space – toggle bar
        registerHotKey(keyCode: UInt32(kVK_Space),
                       modifiers: UInt32(cmdKey | shiftKey),
                       id: toggleHotKeyID,
                       ref: &toggleHotKeyRef,
                       label: "⌘⇧Space (toggle)")

        // ⌘⇧V – new voice session
        registerHotKey(keyCode: UInt32(kVK_ANSI_V),
                       modifiers: UInt32(cmdKey | shiftKey),
                       id: voiceHotKeyID,
                       ref: &voiceHotKeyRef,
                       label: "⌘⇧V (voice session)")
    }

    private func registerHotKey(keyCode: UInt32,
                                modifiers: UInt32,
                                id: UInt32,
                                ref: inout EventHotKeyRef?,
                                label: String) {
        // Unregister any previous registration before re-registering.
        if let existing = ref {
            UnregisterEventHotKey(existing)
            ref = nil
        }

        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status != noErr {
            print("AskBar: RegisterEventHotKey failed for \(label) (status=\(status)). " +
                  "Another app may already own this combination.")
        } else {
            print("AskBar: registered hotkey \(label)")
        }
    }

    // MARK: - Dispatch

    private func handleHotKey(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch id {
            case self.toggleHotKeyID:
                self.toggleCallback?()
            case self.voiceHotKeyID:
                self.voiceSessionCallback?()
            default:
                break
            }
        }
    }

    deinit {
        if let ref = toggleHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = voiceHotKeyRef  { UnregisterEventHotKey(ref) }
        if let handler = eventHandlerRef { RemoveEventHandler(handler) }
    }
}
