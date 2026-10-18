import AppKit
import ApplicationServices
import ZenTouchCore

/// Snaps taps onto nearby clickable elements (buttons, links, checkboxes, fields…), like a phone does,
/// using the Accessibility API. A tap that already lands on something clickable isn't moved.
final class TouchTargeter {
    /// Search radius in points; 0 turns snapping off.
    var radius = 0.0

    private let systemWide = AXUIElementCreateSystemWide()
    /// Stop probing after this long, so a slow app never makes a tap feel laggy.
    private let budget = 0.04
    private var chromiumAppsEnabled: Set<pid_t> = []

    private static let clickableRoles: Set<String> = [
        kAXButtonRole, "AXLink", kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole,
        kAXMenuItemRole, kAXMenuBarItemRole, kAXDisclosureTriangleRole, kAXTextFieldRole, kAXTextAreaRole,
        kAXComboBoxRole, kAXSliderRole, kAXIncrementorRole, kAXColorWellRole, kAXDockItemRole, "AXTab",
    ]
    // Containers that may report a press action but aren't a target you'd aim for.
    private static let containerRoles: Set<String> = [
        kAXApplicationRole, kAXWindowRole, kAXSheetRole, kAXScrollAreaRole, "AXWebArea", kAXGroupRole,
    ]

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    func target(for p: CGPoint) -> CGPoint {
        guard radius > 0 else { return p }
        let deadline = Date().addingTimeInterval(budget)

        if clickable(at: p) != nil { return p }
        for q in TouchArea.samplePoints(around: p, radius: radius) {
            guard Date() < deadline else { break }
            if let hit = clickable(at: q) {
                return hit.frame.map { TouchArea.nearestPoint(in: $0, to: p) } ?? q
            }
        }
        return p
    }

    /// The clickable element at `p` (or the clickable ancestor of what's there, e.g. a link around text).
    private func clickable(at p: CGPoint) -> (element: AXUIElement, frame: CGRect?)? {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &found) == .success,
              var element = found else { return nil }
        enableWebAccessibility(for: element)

        for _ in 0..<3 {
            if isClickable(element) { return (element, frame(of: element)) }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        return nil
    }

    private func isClickable(_ element: AXUIElement) -> Bool {
        guard let role: String = attribute(element, kAXRoleAttribute) else { return false }
        if Self.clickableRoles.contains(role) { return true }
        if Self.containerRoles.contains(role) { return false }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success, let names = actions as? [String] else { return false }
        return names.contains(kAXPressAction)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position: CFTypeRef = attribute(element, kAXPositionAttribute),
              let size: CFTypeRef = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Chrome and Electron apps only expose web page elements to accessibility clients that ask for them.
    private func enableWebAccessibility(for element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, !chromiumAppsEnabled.contains(pid) else { return }
        chromiumAppsEnabled.insert(pid)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
