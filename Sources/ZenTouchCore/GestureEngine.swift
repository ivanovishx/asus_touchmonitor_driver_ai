import CoreGraphics

public enum GesturePhase: Equatable, Sendable { case began, changed, ended }

public enum Shortcut: Equatable, Sendable {
    case missionControl  // 3-finger swipe up
    case appExpose       // 3-finger swipe down
    case spaceLeft       // 3-finger swipe right (content follows the fingers)
    case spaceRight      // 3-finger swipe left
    case nextTab         // 4-finger swipe left
    case previousTab     // 4-finger swipe right
}

/// What the injector should post. Points are global Quartz coordinates.
public enum TouchAction: Equatable, Sendable {
    case move(CGPoint)
    case leftDown(CGPoint, clicks: Int)
    case leftDrag(CGPoint)
    case leftUp(CGPoint, clicks: Int)
    case rightClick(CGPoint)
    /// Finger displacement in points; positive dy means the fingers moved down.
    case scroll(dx: Double, dy: Double, at: CGPoint, phase: GesturePhase)
    /// Relative change in finger spread since the previous event (0.05 = fingers 5% further apart).
    case magnify(amount: Double, at: CGPoint, phase: GesturePhase)
    case shortcut(Shortcut)
}

public struct GestureConfig: Sendable {
    /// Movement (points) below which a touch is still a tap.
    public var slop = 12.0
    /// Holding one finger still this long becomes a right click.
    public var longPress = 0.6
    /// Max duration of a two-finger tap (right click).
    public var twoFingerTapMax = 0.35
    public var doubleTapInterval = 0.4
    public var doubleTapDistance = 30.0
    public var swipeDistance = 80.0
    /// Smallest change in finger spread (points) that can start a pinch instead of a scroll.
    public var pinchMinimum = 8.0

    public init() {}
}

/// Turns frames of touch points into mouse-like actions:
///   1 finger   tap = click (double/triple tap supported), move = drag, hold = right click
///   2 fingers  move = scroll, pinch = zoom, tap = right click
///   3 fingers  swipe = Mission Control / App Exposé / switch Space
///   4 fingers  swipe left/right = next/previous tab (vertical behaves like 3 fingers)
public struct GestureEngine {
    enum Mode { case idle, pending, dragging, scrolling, pinching, consumed }

    public var config: GestureConfig

    private var mode = Mode.idle
    private var startTime = 0.0
    private var anchor = CGPoint.zero        // where the gesture began
    private var lastCentroid = CGPoint.zero
    private var lastCount = 0
    private var maxFingers = 0
    private var travel = CGVector.zero       // centroid movement, excluding jumps when fingers land or lift
    private var lastSpread = 0.0             // mean finger distance from the centroid
    private var spreadChange = 0.0           // accumulated like `travel`
    private var dragClicks = 1
    private var lastTap: (time: Double, point: CGPoint, clicks: Int)?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    public var isIdle: Bool { mode == .idle }

    public mutating func update(_ points: [CGPoint], at t: Double) -> [TouchAction] {
        guard !points.isEmpty else { return end(at: t) }
        let n = points.count
        let c = centroid(points)
        let s = spread(points, around: c)

        if mode == .idle {
            mode = .pending
            startTime = t
            anchor = c
            lastCentroid = c
            lastCount = n
            maxFingers = n
            travel = .zero
            lastSpread = s
            spreadChange = 0
            return n == 1 ? [.move(c)] : []
        }

        maxFingers = max(maxFingers, n)
        // A finger landing or lifting shifts the centroid and spread; that jump is not movement.
        let countChanged = n != lastCount
        let delta = countChanged ? CGVector.zero : CGVector(dx: c.x - lastCentroid.x, dy: c.y - lastCentroid.y)
        let previousSpread = lastSpread
        lastCentroid = c
        lastCount = n
        lastSpread = s
        travel.dx += delta.dx
        travel.dy += delta.dy
        if !countChanged { spreadChange += s - previousSpread }

        switch mode {
        case .pending:
            let moved = length(travel) > config.slop
            switch maxFingers {
            case 1:
                guard moved else { return [] }
                mode = .dragging
                dragClicks = nextClicks(at: anchor, time: startTime)
                return [.move(anchor), .leftDown(anchor, clicks: dragClicks), .leftDrag(c)]
            case 2:
                guard moved || abs(spreadChange) > config.slop else { return [] }
                // A pinch changes the spread at least about as fast as it moves the centroid (exactly as
                // fast when one finger stays put); a scroll moves both fingers together and barely changes it.
                if n == 2, abs(spreadChange) >= config.pinchMinimum, abs(spreadChange) * 2 >= length(travel) {
                    mode = .pinching
                    let start = s - spreadChange
                    return [.move(c), .magnify(amount: start > 1 ? s / start - 1 : 0, at: c, phase: .began)]
                }
                mode = .scrolling
                return [.move(c), .scroll(dx: travel.dx, dy: travel.dy, at: c, phase: .began)]
            default:
                return []  // 3+ fingers: decided on lift
            }
        case .dragging:
            return n == 1 ? [.leftDrag(c)] : []
        case .scrolling:
            return countChanged ? [] : [.scroll(dx: delta.dx, dy: delta.dy, at: c, phase: .changed)]
        case .pinching:
            guard !countChanged, n == 2, previousSpread > 1 else { return [] }
            return [.magnify(amount: s / previousSpread - 1, at: c, phase: .changed)]
        case .idle, .consumed:
            return []
        }
    }

    /// Call periodically (~20 Hz): long press fires even if the controller stops sending reports for a still finger.
    public mutating func tick(at t: Double) -> [TouchAction] {
        guard mode == .pending, maxFingers == 1,
              t - startTime >= config.longPress,
              length(travel) <= config.slop else { return [] }
        mode = .consumed
        return [.rightClick(anchor)]
    }

    private mutating func end(at t: Double) -> [TouchAction] {
        defer { mode = .idle }
        switch mode {
        case .pending:
            switch maxFingers {
            case 1:
                let clicks = nextClicks(at: anchor, time: startTime)
                lastTap = (t, anchor, clicks)
                return [.move(anchor), .leftDown(anchor, clicks: clicks), .leftUp(anchor, clicks: clicks)]
            case 2:
                return t - startTime <= config.twoFingerTapMax ? [.rightClick(lastCentroid)] : []
            default:
                return swipe().map { [.shortcut($0)] } ?? []
            }
        case .dragging:
            lastTap = nil
            return [.leftUp(lastCentroid, clicks: dragClicks)]
        case .scrolling:
            return [.scroll(dx: 0, dy: 0, at: lastCentroid, phase: .ended)]
        case .pinching:
            return [.magnify(amount: 0, at: lastCentroid, phase: .ended)]
        case .idle, .consumed:
            return []
        }
    }

    private func swipe() -> Shortcut? {
        let (dx, dy) = (travel.dx, travel.dy)
        guard max(abs(dx), abs(dy)) >= config.swipeDistance else { return nil }
        if abs(dx) > abs(dy) {
            if maxFingers >= 4 { return dx < 0 ? .nextTab : .previousTab }
            return dx < 0 ? .spaceRight : .spaceLeft
        }
        return dy < 0 ? .missionControl : .appExpose
    }

    private func nextClicks(at p: CGPoint, time: Double) -> Int {
        guard let last = lastTap,
              time - last.time <= config.doubleTapInterval,
              hypot(p.x - last.point.x, p.y - last.point.y) <= config.doubleTapDistance else { return 1 }
        return min(last.clicks + 1, 3)
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }

    private func spread(_ points: [CGPoint], around c: CGPoint) -> Double {
        points.reduce(0) { $0 + hypot($1.x - c.x, $1.y - c.y) } / Double(points.count)
    }

    private func length(_ v: CGVector) -> Double { hypot(v.dx, v.dy) }
}
