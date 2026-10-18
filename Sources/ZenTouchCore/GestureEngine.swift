import CoreGraphics

public enum GesturePhase: Equatable, Sendable { case began, changed, ended }

/// What the injector should post. Points are global Quartz coordinates.
public enum TouchAction: Equatable, Sendable {
    case move(CGPoint)
    case leftDown(CGPoint, clicks: Int)
    case leftDrag(CGPoint)
    case leftUp(CGPoint, clicks: Int)
    /// A tap: move there, press and release. Kept as one action so the app can adjust where it lands.
    case click(CGPoint, clicks: Int)
    case rightClick(CGPoint)
    /// Finger displacement in points; positive dy means the fingers moved down.
    case scroll(dx: Double, dy: Double, at: CGPoint, phase: GesturePhase)
    /// Inertia after a flick: the same units as `scroll`, sent after the fingers have lifted.
    case momentum(dx: Double, dy: Double, at: CGPoint, phase: GesturePhase)
    /// Relative change in finger spread since the previous event (0.05 = fingers 5% further apart).
    case magnify(amount: Double, at: CGPoint, phase: GesturePhase)
    /// A configurable gesture happened; the app looks up its action in the settings.
    case gesture(GestureSlot)
    /// 5 fingers held still: open the gestures panel.
    case openPanel
}

public struct GestureConfig: Sendable {
    /// Movement (points) below which a touch is still a tap.
    public var slop = 12.0
    /// Holding one finger still this long becomes a right click.
    public var longPress = 0.6
    /// Max duration of a multi-finger tap (2 fingers = right click, 3-4 = configurable).
    public var multiFingerTapMax = 0.35
    public var doubleTapInterval = 0.4
    public var doubleTapDistance = 30.0
    public var swipeDistance = 80.0
    /// Smallest change in finger spread (points) that can start a pinch instead of a scroll.
    public var pinchMinimum = 8.0
    /// Finger speed (points/s) at lift-off needed to keep scrolling with inertia.
    public var flickMinSpeed = 300.0
    public var flickMaxSpeed = 6000.0
    /// Seconds for the inertia's speed to fall to 37%; larger glides further.
    public var momentumTimeConstant = 0.4
    public var inertia = true
    /// Multiplies scroll distance and flick speed.
    public var scrollSpeed = 1.0
    /// Finger counts (2...4) whose still hold triggers a gesture. Empty by default, so resting fingers does nothing.
    public var enabledHolds: Set<Int> = []
    public var holdDuration = 0.8
    /// Holding 5 or more fingers still this long opens the gestures panel.
    public var panelHold = 2.0

    public init() {}
}

/// Turns frames of touch points into mouse-like actions:
///   1 finger   tap = click (double/triple tap supported), move = drag, hold = right click
///   2 fingers  move = scroll (flick for inertia), pinch = zoom, tap = right click
///   2-4 fingers  hold, 3-4 fingers tap, 3-4 fingers swipe = configurable (see GestureSlot)
///   5 fingers  hold = open the gestures panel
public struct GestureEngine {
    enum Mode { case idle, pending, dragging, scrolling, pinching, consumed }

    public var config: GestureConfig

    private var mode = Mode.idle
    private var startTime = 0.0
    private var anchor = CGPoint.zero        // where the gesture began
    private var lastCentroid = CGPoint.zero
    private var lastCount = 0
    private var maxFingers = 0
    private var allFingersDownAt = 0.0      // when the finger count last reached its maximum, for holds
    private var travel = CGVector.zero       // centroid movement, excluding jumps when fingers land or lift
    private var lastSpread = 0.0             // mean finger distance from the centroid
    private var spreadChange = 0.0           // accumulated like `travel`
    private var dragClicks = 1
    private var lastTap: (time: Double, point: CGPoint, clicks: Int)?
    private var scrollSamples: [(time: Double, travel: CGVector)] = []  // recent positions, for flick speed
    private var momentum = Momentum()
    private var caughtMomentum = false       // this touch stopped a glide, so it isn't a tap

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
            // Touching the screen stops a glide, like on a phone.
            caughtMomentum = momentum.isActive
            let stopped = momentum.cancel()
            mode = .pending
            startTime = t
            anchor = c
            lastCentroid = c
            lastCount = n
            maxFingers = n
            allFingersDownAt = t
            travel = .zero
            lastSpread = s
            spreadChange = 0
            return (stopped.map { [$0] } ?? []) + (n == 1 ? [.move(c)] : [])
        }

        if n > maxFingers {
            maxFingers = n
            allFingersDownAt = t
        }
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
                scrollSamples = [(t, travel)]
                let k = config.scrollSpeed
                return [.move(c), .scroll(dx: travel.dx * k, dy: travel.dy * k, at: c, phase: .began)]
            default:
                return []  // 3+ fingers: decided on lift
            }
        case .dragging:
            return n == 1 ? [.leftDrag(c)] : []
        case .scrolling:
            guard !countChanged else { return [] }
            scrollSamples.append((t, travel))
            scrollSamples.removeAll { t - $0.time > 0.1 }
            return [.scroll(dx: delta.dx * config.scrollSpeed, dy: delta.dy * config.scrollSpeed, at: c, phase: .changed)]
        case .pinching:
            guard !countChanged, n == 2, previousSpread > 1 else { return [] }
            return [.magnify(amount: s / previousSpread - 1, at: c, phase: .changed)]
        case .idle, .consumed:
            return []
        }
    }

    /// Call at ~60 Hz: drives the inertia glide, and fires long press even if the controller stops
    /// sending reports for a still finger.
    public mutating func tick(at t: Double) -> [TouchAction] {
        if let glide = momentum.step(at: t) { return [glide] }

        // Multi-finger holds: every finger still down and still.
        if mode == .pending, maxFingers >= 2, lastCount == maxFingers, !caughtMomentum,
           length(travel) <= config.slop, abs(spreadChange) <= config.slop {
            let held = t - allFingersDownAt
            if maxFingers >= 5, held >= config.panelHold {
                mode = .consumed
                return [.openPanel]
            }
            if config.enabledHolds.contains(maxFingers), held >= config.holdDuration {
                mode = .consumed
                return [.gesture(.hold(maxFingers))]
            }
        }

        guard mode == .pending, maxFingers == 1, !caughtMomentum,
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
                guard !caughtMomentum else { return [] }
                let clicks = nextClicks(at: anchor, time: startTime)
                lastTap = (t, anchor, clicks)
                return [.click(anchor, clicks: clicks)]
            case 2:
                return t - startTime <= config.multiFingerTapMax ? [.rightClick(lastCentroid)] : []
            case 3, 4:
                if t - startTime <= config.multiFingerTapMax, length(travel) <= config.slop {
                    return [.gesture(.tap(maxFingers))]
                }
                return swipe().map { [.gesture(.swipe(maxFingers, $0))] } ?? []
            default:
                return []  // 5+ fingers are reserved for the panel hold
            }
        case .dragging:
            lastTap = nil
            return [.leftUp(lastCentroid, clicks: dragClicks)]
        case .scrolling:
            if config.inertia, let velocity = flickVelocity(at: t) {
                momentum.timeConstant = config.momentumTimeConstant
                momentum.start(velocity: velocity, at: lastCentroid, time: t)
            }
            return [.scroll(dx: 0, dy: 0, at: lastCentroid, phase: .ended)]
        case .pinching:
            return [.magnify(amount: 0, at: lastCentroid, phase: .ended)]
        case .idle, .consumed:
            return []
        }
    }

    /// Finger velocity over the last ~0.1 s, if they were still moving fast when they lifted.
    private func flickVelocity(at t: Double) -> CGVector? {
        guard let first = scrollSamples.first, let last = scrollSamples.last,
              t - last.time < 0.05,            // fingers stopped before lifting: no flick
              last.time - first.time >= 0.01 else { return nil }
        let k = config.scrollSpeed / (last.time - first.time)
        var v = CGVector(dx: (last.travel.dx - first.travel.dx) * k, dy: (last.travel.dy - first.travel.dy) * k)
        let speed = length(v)
        guard speed >= config.flickMinSpeed else { return nil }
        if speed > config.flickMaxSpeed {
            v = CGVector(dx: v.dx / speed * config.flickMaxSpeed, dy: v.dy / speed * config.flickMaxSpeed)
        }
        return v
    }

    private func swipe() -> SwipeDirection? {
        let (dx, dy) = (travel.dx, travel.dy)
        guard max(abs(dx), abs(dy)) >= config.swipeDistance else { return nil }
        if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .up : .down
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
