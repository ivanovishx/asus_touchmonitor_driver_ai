import CoreGraphics
import Foundation

/// Smartphone-style inertia after a flick: the content keeps scrolling while its speed decays
/// exponentially, like iOS scroll views and the momentum events a MacBook trackpad sends.
struct Momentum {
    /// Seconds for the speed to fall to 37%; larger glides further.
    var timeConstant = 0.4
    /// Speed (points/s) below which the glide ends.
    var stopSpeed = 20.0

    private(set) var isActive = false
    private var velocity = CGVector.zero
    private var point = CGPoint.zero
    private var lastTime = 0.0
    private var started = false

    mutating func start(velocity: CGVector, at point: CGPoint, time: Double) {
        self.velocity = velocity
        self.point = point
        lastTime = time
        started = false
        isActive = true
    }

    /// The scroll for the time since the last step, or nil when not gliding.
    mutating func step(at t: Double) -> TouchAction? {
        guard isActive else { return nil }
        let dt = max(t - lastTime, 0)
        lastTime = t
        // Exact distance covered under exponential decay, so the glide is the same at any tick rate.
        let decay = exp(-dt / timeConstant)
        let k = timeConstant * (1 - decay)
        let dx = velocity.dx * k, dy = velocity.dy * k
        velocity = CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)

        if started, hypot(velocity.dx, velocity.dy) < stopSpeed {
            isActive = false
            return .momentum(dx: dx, dy: dy, at: point, phase: .ended)
        }
        defer { started = true }
        return .momentum(dx: dx, dy: dy, at: point, phase: started ? .changed : .began)
    }

    /// Stops a glide (a finger touched the screen), returning its end event.
    mutating func cancel() -> TouchAction? {
        guard isActive else { return nil }
        isActive = false
        return started ? .momentum(dx: 0, dy: 0, at: point, phase: .ended) : nil
    }
}
