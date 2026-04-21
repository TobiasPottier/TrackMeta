import AppKit
import Carbon.HIToolbox

/// Registers a single process-wide hotkey using the Carbon Events API and
/// invokes `handler` on the main actor when the key combo is pressed anywhere
/// in macOS. The registration is released on `deinit`.
///
/// Default binding: ⌃⌥ Space — not claimed by macOS defaults (Spotlight is
/// ⌘Space, emoji picker is ⌃⌘Space, Siri is ⌥Space-hold) or common apps.
@MainActor
final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    init(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(controlKey | optionKey),
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        install(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func install(keyCode: UInt32, modifiers: UInt32) {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return status }
                let instance = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in instance.handler() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x544D4B59), id: 1) // 'TMKY'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
