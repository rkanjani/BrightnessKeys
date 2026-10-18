import AppKit
import ApplicationServices

/// Intercepts the brightness keys. The handler returns true when it consumed the key;
/// otherwise the event passes through to macOS untouched.
final class BrightnessKeyTap {
    typealias Handler = (_ up: Bool, _ isDown: Bool, _ fine: Bool) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var pollTimer: Timer?

    // NX_SYSDEFINED media-key subtype and key types from IOKit/hidsystem/ev_keymap.h.
    private static let systemDefinedType = CGEventType(rawValue: 14)!
    private static let mediaKeySubtype: Int16 = 8
    private static let brightnessUp = 2
    private static let brightnessDown = 3
    // Some keyboards send brightness as ordinary key codes instead.
    private static let keyCodeBrightnessUp: Int64 = 144
    private static let keyCodeBrightnessDown: Int64 = 145

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isActive: Bool { tap != nil }

    /// Starts the tap, or waits for Accessibility permission and starts it once granted.
    func start(prompt: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), install() { return }
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.install() else { return }
            timer.invalidate()
            self.pollTimer = nil
            NotificationCenter.default.post(name: .keyTapStateChanged, object: nil)
        }
    }

    private func install() -> Bool {
        let mask = (CGEventMask(1) << Self.systemDefinedType.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            let me = Unmanaged<BrightnessKeyTap>.fromOpaque(info!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let flags = event.flags
        let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)

        if type == Self.systemDefinedType {
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == Self.mediaKeySubtype else { return pass }
            let keyType = (ns.data1 & 0xFFFF_0000) >> 16
            guard keyType == Self.brightnessUp || keyType == Self.brightnessDown else { return pass }
            let isDown = ((ns.data1 & 0xFF00) >> 8) == 0x0A
            return handler(keyType == Self.brightnessUp, isDown, fine) ? nil : pass
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == Self.keyCodeBrightnessUp || code == Self.keyCodeBrightnessDown else { return pass }
        return handler(code == Self.keyCodeBrightnessUp, type == .keyDown, fine) ? nil : pass
    }
}

extension Notification.Name {
    static let keyTapStateChanged = Notification.Name("keyTapStateChanged")
}
