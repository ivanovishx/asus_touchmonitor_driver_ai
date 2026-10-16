import AppKit
import ZenTouchCore

/// Finds the touch display. Looked up again at the start of every gesture, so plugging the ZenScreen in
/// after launch, reconnecting it (which can change its CGDirectDisplayID) or rearranging displays just works.
enum DisplayLocator {
    /// The screen whose name contains `query`, else the first external screen.
    static func find(nameContaining query: String) -> (id: CGDirectDisplayID, name: String)? {
        let screens = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, name: String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        }
        return screens.first { $0.name.localizedCaseInsensitiveContains(query) }
            ?? screens.first { CGDisplayIsBuiltin($0.id) == 0 }
    }

    static func mapper(nameContaining query: String, calibration: Calibration) -> DisplayMapper? {
        guard let id = find(nameContaining: query)?.id else { return nil }
        return DisplayMapper(bounds: CGDisplayBounds(id), rotation: CGDisplayRotation(id), calibration: calibration)
    }
}
