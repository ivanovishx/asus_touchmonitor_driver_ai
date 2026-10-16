import CoreGraphics
import Foundation
import ZenTouchCore

enum ZoomStyle {
    /// Trackpad-style magnify gestures: smooth pinch zoom in Chrome, Safari, Preview, Maps, Photos…
    case gesture
    /// ⌘+ / ⌘− steps, for apps that ignore synthetic gestures.
    case keys
}

/// Posts synthetic input at the HID level, so apps can't tell it apart from a real mouse/trackpad.
final class EventInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    // Pixel scroll deltas are integers; carry the fractions so slow scrolls still move.
    private var scrollRemainder = CGVector.zero
    private let zoomStyle: ZoomStyle
    // Pinch progress (log scale) not yet turned into a ⌘+ / ⌘− step.
    private var zoomProgress = 0.0
    private static let zoomStep = log(1.2)

    // Not exposed as named CGEventField / CGEventType cases. These are the values a real trackpad's
    // magnify events carry (NSEventTypeGesture with a zoom subtype).
    private static let scrollPhaseField = CGEventField(rawValue: 99)!     // kCGScrollWheelEventScrollPhase
    private static let gestureType = CGEventType(rawValue: 29)!           // kCGSEventGesture
    private static let gestureHIDTypeField = CGEventField(rawValue: 110)!  // kCGEventGestureHIDType
    private static let gestureZoomField = CGEventField(rawValue: 113)!     // kCGEventGestureZoomValue
    private static let gesturePhaseField = CGEventField(rawValue: 132)!    // kCGEventGesturePhase
    private static let hidZoomEventType: Int64 = 8                        // kIOHIDEventTypeZoom

    init(zoomStyle: ZoomStyle = .gesture) {
        self.zoomStyle = zoomStyle
    }

    func perform(_ action: TouchAction) {
        switch action {
        case .move(let p):
            mouse(.mouseMoved, at: p)
        case .leftDown(let p, let clicks):
            mouse(.leftMouseDown, at: p, clicks: clicks)
        case .leftDrag(let p):
            mouse(.leftMouseDragged, at: p)
        case .leftUp(let p, let clicks):
            mouse(.leftMouseUp, at: p, clicks: clicks)
        case .rightClick(let p):
            mouse(.mouseMoved, at: p)
            mouse(.rightMouseDown, at: p, button: .right)
            mouse(.rightMouseUp, at: p, button: .right)
        case .scroll(let dx, let dy, let p, let phase):
            scroll(dx: dx, dy: dy, at: p, phase: phase)
        case .magnify(let amount, let p, let phase):
            magnify(amount, at: p, phase: phase)
        case .shortcut(let shortcut):
            press(shortcut)
        }
    }

    private func mouse(_ type: CGEventType, at p: CGPoint, button: CGMouseButton = .left, clicks: Int = 1) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        event.post(tap: .cghidEventTap)
    }

    private func scroll(dx: Double, dy: Double, at p: CGPoint, phase: GesturePhase) {
        if phase == .began { scrollRemainder = .zero }
        // Direct manipulation: content follows the fingers, so finger-down (dy > 0) is a positive wheel delta.
        let x = dx + scrollRemainder.dx, y = dy + scrollRemainder.dy
        let wheelX = x.rounded(.towardZero), wheelY = y.rounded(.towardZero)
        scrollRemainder = CGVector(dx: x - wheelX, dy: y - wheelY)

        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(wheelY), wheel2: Int32(wheelX), wheel3: 0) else { return }
        event.location = p
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(Self.scrollPhaseField, value: Self.phaseValue(phase))
        event.post(tap: .cghidEventTap)
    }

    private func magnify(_ amount: Double, at p: CGPoint, phase: GesturePhase) {
        // Gestures and ⌘+/⌘− both go to the window under the cursor.
        if phase == .began { mouse(.mouseMoved, at: p) }

        switch zoomStyle {
        case .gesture:
            guard let event = CGEvent(source: source) else { return }
            event.type = Self.gestureType
            event.location = p
            event.setIntegerValueField(Self.gestureHIDTypeField, value: Self.hidZoomEventType)
            event.setDoubleValueField(Self.gestureZoomField, value: amount)
            event.setIntegerValueField(Self.gesturePhaseField, value: Self.phaseValue(phase))
            event.post(tap: .cghidEventTap)
        case .keys:
            if phase == .began { zoomProgress = 0 }
            zoomProgress += log1p(amount)
            while zoomProgress >= Self.zoomStep {
                key(24, flags: .maskCommand)  // ⌘=  (zoom in)
                zoomProgress -= Self.zoomStep
            }
            while zoomProgress <= -Self.zoomStep {
                key(27, flags: .maskCommand)  // ⌘-  (zoom out)
                zoomProgress += Self.zoomStep
            }
        }
    }

    private static func phaseValue(_ phase: GesturePhase) -> Int64 {
        switch phase {
        case .began: 1
        case .changed: 2
        case .ended: 4
        }
    }

    private func press(_ shortcut: Shortcut) {
        let arrow: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        let (key, flags): (CGKeyCode, CGEventFlags) = switch shortcut {
        case .spaceLeft: (123, arrow)       // ⌃←
        case .spaceRight: (124, arrow)      // ⌃→
        case .appExpose: (125, arrow)       // ⌃↓
        case .missionControl: (126, arrow)  // ⌃↑
        // ⌃Tab / ⌃⇧Tab: tab switching in Chrome, Safari, Finder, Terminal and most tabbed apps.
        case .nextTab: (48, [.maskControl])
        case .previousTab: (48, [.maskControl, .maskShift])
        }
        self.key(key, flags: flags)
    }

    private func key(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
