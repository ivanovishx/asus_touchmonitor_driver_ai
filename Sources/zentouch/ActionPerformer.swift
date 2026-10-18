import AppKit
import ZenTouchCore

/// Runs the action configured for a gesture.
final class ActionPerformer {
    private let injector: EventInjector

    init(injector: EventInjector) {
        self.injector = injector
    }

    func perform(_ action: GestureAction) {
        switch action {
        case .none:
            break
        case .keys(let combo):
            guard combo.isSet else { return }
            injector.key(CGKeyCode(combo.keyCode), flags: CGEventFlags(rawValue: combo.modifiers))
        case .openApp(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        case .system(let action):
            perform(action)
        }
    }

    private func perform(_ action: SystemAction) {
        let cmd = CGEventFlags.maskCommand, ctrl = CGEventFlags.maskControl, shift = CGEventFlags.maskShift
        switch action {
        // Mission Control's own binary works even if its keyboard shortcuts are turned off.
        case .missionControl: missionControl()
        case .appExpose: missionControl("2")
        case .showDesktop: missionControl("1")
        case .apps: open("/System/Applications/Apps.app")
        case .nextSpace: injector.key(124, flags: ctrl)          // ⌃→
        case .previousSpace: injector.key(123, flags: ctrl)      // ⌃←
        case .nextTab: injector.key(48, flags: ctrl)             // ⌃⇥
        case .previousTab: injector.key(48, flags: [ctrl, shift])
        case .newTab: injector.key(17, flags: cmd)               // ⌘T
        case .closeTab: injector.key(13, flags: cmd)             // ⌘W
        case .reopenTab: injector.key(17, flags: [cmd, shift])   // ⌘⇧T
        case .back: injector.key(33, flags: cmd)                 // ⌘[
        case .forward: injector.key(30, flags: cmd)              // ⌘]
        case .spotlight: injector.key(49, flags: cmd)            // ⌘Space
        case .screenshot: injector.key(23, flags: [cmd, shift])  // ⌘⇧5
        case .fullScreen: injector.key(3, flags: [cmd, ctrl])    // ⌃⌘F
        case .minimizeWindow: injector.key(46, flags: cmd)       // ⌘M
        case .hideApp: injector.key(4, flags: cmd)               // ⌘H
        case .lockScreen: injector.key(12, flags: [cmd, ctrl])   // ⌃⌘Q
        case .copy: injector.key(8, flags: cmd)                  // ⌘C
        case .paste: injector.key(9, flags: cmd)                 // ⌘V
        case .undo: injector.key(6, flags: cmd)                  // ⌘Z
        case .redo: injector.key(6, flags: [cmd, shift])         // ⌘⇧Z
        case .zoomIn: injector.key(24, flags: cmd)               // ⌘=
        case .zoomOut: injector.key(27, flags: cmd)              // ⌘-
        case .actualSize: injector.key(29, flags: cmd)           // ⌘0
        case .rightClick: injector.perform(.rightClick(cursor()))
        case .middleClick: injector.middleClick(at: cursor())
        // NX_KEYTYPE_* media keys.
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .mute: mediaKey(7)
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        }
    }

    private func missionControl(_ argument: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        process.arguments = argument.map { [$0] } ?? []
        do {
            try process.run()
        } catch {
            injector.key(argument == nil ? 126 : 125, flags: .maskControl)  // ⌃↑ / ⌃↓
        }
    }

    private func open(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    private func cursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Media keys aren't key codes: they're "system defined" events, like the ones the F-row sends.
    private func mediaKey(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA00 : 0xB00
            NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | state, data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
