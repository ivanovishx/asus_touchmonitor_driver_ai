import CoreGraphics

/// Corrections for a panel whose axes don't line up with the image (mounting, firmware quirks).
public struct Calibration: Equatable, Sendable {
    public var swapXY = false
    public var flipX = false
    public var flipY = false
    /// Raw panel range actually reachable at the screen edges, normalized. Lets you trim a bezel offset.
    public var minX = 0.0, maxX = 1.0, minY = 0.0, maxY = 1.0
    /// Shift (points) added to every touch, for a panel that reads slightly beside your finger.
    public var offsetX = 0.0, offsetY = 0.0

    public init() {}
}

/// Maps normalized panel coordinates onto a display in global screen space
/// (Quartz coordinates: origin at the top-left of the main display, y grows downward).
public struct DisplayMapper {
    public var bounds: CGRect
    /// Display rotation in degrees as reported by CGDisplayRotation (0, 90, 180, 270).
    public var rotation: Double
    public var calibration: Calibration

    public init(bounds: CGRect, rotation: Double = 0, calibration: Calibration = Calibration()) {
        self.bounds = bounds
        self.rotation = rotation
        self.calibration = calibration
    }

    public func map(_ contact: Contact) -> CGPoint {
        var u = contact.x, v = contact.y
        let c = calibration

        u = (u - c.minX) / max(c.maxX - c.minX, .ulpOfOne)
        v = (v - c.minY) / max(c.maxY - c.minY, .ulpOfOne)
        if c.swapXY { swap(&u, &v) }
        if c.flipX { u = 1 - u }
        if c.flipY { v = 1 - v }

        // The panel is glued to the glass, so when macOS rotates the image the touch axes must rotate too.
        switch Int(rotation.rounded()) % 360 {
        case 90: (u, v) = (1 - v, u)
        case 180: (u, v) = (1 - u, 1 - v)
        case 270: (u, v) = (v, 1 - u)
        default: break
        }

        u = min(max(u, 0), 1)
        v = min(max(v, 0), 1)
        // Stay one point inside the right/bottom edge so the cursor never jumps to the neighbouring display.
        let x = bounds.minX + u * (bounds.width - 1) + c.offsetX
        let y = bounds.minY + v * (bounds.height - 1) + c.offsetY
        return CGPoint(
            x: min(max(x, bounds.minX), bounds.maxX - 1),
            y: min(max(y, bounds.minY), bounds.maxY - 1)
        )
    }
}
