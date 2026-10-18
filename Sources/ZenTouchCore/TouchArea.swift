import CoreGraphics
import Foundation

/// Geometry for snapping a tap onto a nearby target, like a phone's enlarged touch area.
public enum TouchArea {
    /// Points to probe around `center`, nearest first: rings every `step` points out to `radius`,
    /// spaced about `step` apart along each ring. The center itself is not included.
    public static func samplePoints(around center: CGPoint, radius: Double, step: Double = 8) -> [CGPoint] {
        guard radius > 0, step > 0 else { return [] }
        var points: [CGPoint] = []
        var r = min(step, radius)
        while r <= radius + 0.001 {
            let count = max(8, Int((2 * .pi * r / step).rounded()))
            for i in 0..<count {
                let angle = 2 * .pi * Double(i) / Double(count)
                points.append(CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
            }
            r += step
        }
        return points
    }

    /// The point inside `frame` (inset slightly, so the click isn't on its very edge) closest to `p`.
    public static func nearestPoint(in frame: CGRect, to p: CGPoint, inset: Double = 3) -> CGPoint {
        let f = frame.width > 2 * inset && frame.height > 2 * inset ? frame.insetBy(dx: inset, dy: inset) : frame
        return CGPoint(x: min(max(p.x, f.minX), f.maxX), y: min(max(p.y, f.minY), f.maxY))
    }
}
