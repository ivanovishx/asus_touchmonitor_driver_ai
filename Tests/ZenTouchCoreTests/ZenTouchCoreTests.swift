import CoreGraphics
import Foundation
import Testing
@testable import ZenTouchCore

/// Builds a report-6 payload in the eGalax layout: count, 5 x (tip, id, x16, y16, pad4), scan time.
func payload(count: Int, _ slots: [(tip: Bool, id: Int, x: Int, y: Int)]) -> [UInt8] {
    var bytes = [UInt8(count)]
    for i in 0..<5 {
        if i < slots.count {
            let s = slots[i]
            bytes += [s.tip ? 1 : 0, UInt8(s.id), UInt8(s.x & 0xFF), UInt8(s.x >> 8), UInt8(s.y & 0xFF), UInt8(s.y >> 8), 0, 0, 0, 0]
        } else {
            bytes += [UInt8](repeating: 0, count: 10)
        }
    }
    return bytes + [0, 0, 0, 0]
}

@Suite struct ParserTests {
    @Test func singleContact() {
        var parser = EGalaxReportParser()
        let frame = parser.feed(payload(count: 1, [(true, 3, 4095, 0)]))
        #expect(frame == [Contact(id: 3, x: 1, y: 0)])
    }

    @Test func liftedContactIsDropped() {
        var parser = EGalaxReportParser()
        #expect(parser.feed(payload(count: 1, [(false, 3, 100, 100)])) == [])
    }

    @Test func hybridFrameWaitsForContinuation() {
        var parser = EGalaxReportParser()
        let five = (0..<5).map { (tip: true, id: $0, x: 0, y: 0) }
        #expect(parser.feed(payload(count: 7, five)) == nil)
        let rest = parser.feed(payload(count: 0, [(true, 5, 0, 0), (true, 6, 0, 0)]))
        #expect(rest?.map(\.id) == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func strayContinuationIsIgnored() {
        var parser = EGalaxReportParser()
        #expect(parser.feed(payload(count: 0, [(true, 1, 0, 0)])) == nil)
    }

    @Test func shortReportIsIgnored() {
        var parser = EGalaxReportParser()
        #expect(parser.feed([1, 1, 0]) == nil)
    }
}

@Suite struct MapperTests {
    // ZenScreen placed to the right of a 1512-wide main display.
    let bounds = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    @Test func mapsCornersIntoDisplay() {
        let m = DisplayMapper(bounds: bounds)
        #expect(m.map(Contact(id: 0, x: 0, y: 0)) == CGPoint(x: 1512, y: 0))
        #expect(m.map(Contact(id: 0, x: 1, y: 1)) == CGPoint(x: 1512 + 1919, y: 1079))
    }

    @Test func rotation180() {
        let m = DisplayMapper(bounds: bounds, rotation: 180)
        #expect(m.map(Contact(id: 0, x: 0, y: 0)) == CGPoint(x: 1512 + 1919, y: 1079))
    }

    @Test func offsetShiftsTouches() {
        var c = Calibration()
        c.offsetX = 10
        c.offsetY = -5
        let m = DisplayMapper(bounds: bounds, calibration: c)
        #expect(m.map(Contact(id: 0, x: 0.5, y: 0.5)) == CGPoint(x: 1512 + 959.5 + 10, y: 539.5 - 5))
    }

    @Test func offsetNeverLeavesTheDisplay() {
        var c = Calibration()
        c.offsetX = -40
        c.offsetY = 40
        let m = DisplayMapper(bounds: bounds, calibration: c)
        #expect(m.map(Contact(id: 0, x: 0, y: 1)) == CGPoint(x: 1512, y: 1079))
    }

    @Test func flipX() {
        var c = Calibration()
        c.flipX = true
        let m = DisplayMapper(bounds: bounds, calibration: c)
        #expect(m.map(Contact(id: 0, x: 0, y: 0)) == CGPoint(x: 1512 + 1919, y: 0))
    }
}

@Suite struct GestureTests {
    let p = CGPoint(x: 100, y: 100)

    @Test func tapClicks() {
        var e = GestureEngine()
        #expect(e.update([p], at: 0) == [.move(p)])
        #expect(e.update([], at: 0.1) == [.click(p, clicks: 1)])
    }

    @Test func doubleTap() {
        var e = GestureEngine()
        _ = e.update([p], at: 0); _ = e.update([], at: 0.1)
        _ = e.update([p], at: 0.25)
        #expect(e.update([], at: 0.3) == [.click(p, clicks: 2)])
    }

    @Test func dragAfterSlop() {
        var e = GestureEngine()
        _ = e.update([p], at: 0)
        #expect(e.update([CGPoint(x: 105, y: 100)], at: 0.05) == [])
        let q = CGPoint(x: 130, y: 100)
        #expect(e.update([q], at: 0.1) == [.move(p), .leftDown(p, clicks: 1), .leftDrag(q)])
        #expect(e.update([], at: 0.2) == [.leftUp(q, clicks: 1)])
    }

    @Test func longPressRightClicks() {
        var e = GestureEngine()
        _ = e.update([p], at: 0)
        #expect(e.tick(at: 0.3) == [])
        #expect(e.tick(at: 0.7) == [.rightClick(p)])
        #expect(e.update([], at: 1.0) == [])
    }

    @Test func twoFingerScroll() {
        var e = GestureEngine()
        let a = CGPoint(x: 100, y: 100), b = CGPoint(x: 200, y: 100)
        _ = e.update([a], at: 0)
        _ = e.update([a, b], at: 0.02)  // second finger lands: no movement
        let down = { (d: Double) in [CGPoint(x: 100, y: 100 + d), CGPoint(x: 200, y: 100 + d)] }
        let began = e.update(down(20), at: 0.1)
        #expect(began.last == .scroll(dx: 0, dy: 20, at: CGPoint(x: 150, y: 120), phase: .began))
        #expect(e.update(down(25), at: 0.12) == [.scroll(dx: 0, dy: 5, at: CGPoint(x: 150, y: 125), phase: .changed)])
        #expect(e.update([], at: 0.2) == [.scroll(dx: 0, dy: 0, at: CGPoint(x: 150, y: 125), phase: .ended)])
    }

    @Test func twoFingerTapRightClicks() {
        var e = GestureEngine()
        let a = CGPoint(x: 100, y: 100), b = CGPoint(x: 200, y: 100)
        _ = e.update([a, b], at: 0)
        #expect(e.update([], at: 0.15) == [.rightClick(CGPoint(x: 150, y: 100))])
    }

    @Test func threeFingerSwipeUp() {
        var e = GestureEngine()
        let fingers = { (y: Double) in [CGPoint(x: 100, y: y), CGPoint(x: 150, y: y), CGPoint(x: 200, y: y)] }
        _ = e.update(fingers(500), at: 0)
        _ = e.update(fingers(400), at: 0.1)
        #expect(e.update([], at: 0.2) == [.gesture(.swipe(3, .up))])
    }

    /// Two fingers on a horizontal line, `gap` apart, centred on (cx, 300).
    func pair(gap: Double, cx: Double = 400) -> [CGPoint] {
        [CGPoint(x: cx - gap / 2, y: 300), CGPoint(x: cx + gap / 2, y: 300)]
    }

    @Test func pinchOutZoomsIn() {
        var e = GestureEngine()
        _ = e.update(pair(gap: 100), at: 0)
        #expect(e.update(pair(gap: 110), at: 0.05) == [])  // spread +5: below the threshold
        let began = e.update(pair(gap: 140), at: 0.1)     // spread 50 → 70
        #expect(began.first == .move(CGPoint(x: 400, y: 300)))
        guard case .magnify(let a, _, .began) = began.last else { Issue.record("no pinch: \(began)"); return }
        #expect(abs(a - 0.4) < 1e-9)
        guard case .magnify(let b, _, .changed) = e.update(pair(gap: 210), at: 0.15).last else { Issue.record(); return }
        #expect(abs(b - 0.5) < 1e-9)                      // 140 → 210
        #expect(e.update([], at: 0.2) == [.magnify(amount: 0, at: CGPoint(x: 400, y: 300), phase: .ended)])
    }

    @Test func pinchInZoomsOut() {
        var e = GestureEngine()
        _ = e.update(pair(gap: 200), at: 0)
        guard case .magnify(let a, _, .began) = e.update(pair(gap: 150), at: 0.1).last else { Issue.record(); return }
        #expect(a < 0)
    }

    @Test func pinchWithOneFingerStillIsAPinch() {
        var e = GestureEngine()
        let fixed = CGPoint(x: 300, y: 300)
        _ = e.update([fixed, CGPoint(x: 400, y: 300)], at: 0)
        let actions = e.update([fixed, CGPoint(x: 430, y: 300)], at: 0.1)
        guard case .magnify(_, _, .began) = actions.last else { Issue.record("expected pinch: \(actions)"); return }
    }

    @Test func parallelMoveIsStillAScroll() {
        var e = GestureEngine()
        _ = e.update(pair(gap: 100, cx: 400), at: 0)
        let actions = e.update(pair(gap: 104, cx: 430), at: 0.1)  // small spread drift while moving 30 pt
        guard case .scroll(_, _, _, .began) = actions.last else { Issue.record("expected scroll: \(actions)"); return }
    }

    /// Scrolls two fingers down at `speed` points/s, sampled at 100 Hz for 0.2 s, and returns the lift time.
    func scrollDown(_ e: inout GestureEngine, speed: Double) -> Double {
        var t = 0.0
        _ = e.update(pair(gap: 100), at: t)
        for i in 1...20 {
            t = Double(i) * 0.01
            _ = e.update(pair(gap: 100).map { CGPoint(x: $0.x, y: $0.y + speed * t) }, at: t)
        }
        return t
    }

    func glide(_ e: inout GestureEngine, from t0: Double, seconds: Double) -> [TouchAction] {
        stride(from: t0 + 1.0 / 60, through: t0 + seconds, by: 1.0 / 60).flatMap { e.tick(at: $0) }
    }

    @Test func flickKeepsScrollingAndSlowsDown() {
        var e = GestureEngine()
        let lift = scrollDown(&e, speed: 1500)
        #expect(e.update([], at: lift).last.map { if case .scroll(_, _, _, .ended) = $0 { true } else { false } } == true)

        let actions = glide(&e, from: lift, seconds: 4)
        let deltas = actions.compactMap { if case .momentum(_, let dy, _, _) = $0 { dy } else { nil } }
        guard case .momentum(_, _, _, .began) = actions.first,
              case .momentum(_, _, _, .ended) = actions.last else { Issue.record("bad glide: \(actions.prefix(3))"); return }
        #expect(deltas.allSatisfy { $0 >= 0 })                  // keeps going the way the fingers went
        #expect(deltas[0] > deltas[10] && deltas[10] > deltas[30])  // and decelerates
        let distance = deltas.reduce(0, +)
        #expect(distance > 500 && distance < 650)               // ≈ speed × time constant = 600 pt
        #expect(glide(&e, from: lift + 4, seconds: 0.5).isEmpty)
    }

    @Test func slowLiftDoesNotGlide() {
        var e = GestureEngine()
        let lift = scrollDown(&e, speed: 150)
        _ = e.update([], at: lift)
        #expect(glide(&e, from: lift, seconds: 0.5).isEmpty)
    }

    @Test func pausingBeforeLiftDoesNotGlide() {
        var e = GestureEngine()
        let lift = scrollDown(&e, speed: 1500)
        _ = e.update([], at: lift + 0.2)  // fingers held still for 0.2 s, then lifted
        #expect(glide(&e, from: lift + 0.2, seconds: 0.5).isEmpty)
    }

    @Test func touchStopsGlideWithoutClicking() {
        var e = GestureEngine()
        let lift = scrollDown(&e, speed: 1500)
        _ = e.update([], at: lift)
        _ = glide(&e, from: lift, seconds: 0.2)
        let touch = e.update([p], at: lift + 0.25)
        guard case .momentum(0, 0, _, .ended) = touch.first else { Issue.record("glide not stopped: \(touch)"); return }
        #expect(e.update([], at: lift + 0.3) == [])           // the catching tap doesn't click
        #expect(glide(&e, from: lift + 0.3, seconds: 0.5).isEmpty)
        _ = e.update([p], at: lift + 1)                       // the next tap clicks again
        #expect(e.update([], at: lift + 1.1) == [.click(p, clicks: 1)])
    }

    let four = { (x: Double) in (0..<4).map { CGPoint(x: x + Double($0) * 50, y: 300) } }

    @Test func fourFingerSwipeLeft() {
        var e = GestureEngine()
        _ = e.update(four(600), at: 0)
        _ = e.update(four(450), at: 0.1)
        #expect(e.update([], at: 0.2) == [.gesture(.swipe(4, .left))])
    }

    @Test func fourFingerSwipeRight() {
        var e = GestureEngine()
        _ = e.update(four(300), at: 0)
        _ = e.update(four(450), at: 0.1)
        #expect(e.update([], at: 0.2) == [.gesture(.swipe(4, .right))])
    }

    @Test func threeFingerSwipeLeft() {
        var e = GestureEngine()
        let three = { (x: Double) in (0..<3).map { CGPoint(x: x + Double($0) * 50, y: 300) } }
        _ = e.update(three(600), at: 0)
        _ = e.update(three(450), at: 0.1)
        #expect(e.update([], at: 0.2) == [.gesture(.swipe(3, .left))])
    }

    func fingers(_ n: Int, x: Double = 300) -> [CGPoint] {
        (0..<n).map { CGPoint(x: x + Double($0) * 60, y: 400) }
    }

    @Test func holdIsOffUntilItHasAnAction() {
        var e = GestureEngine()
        _ = e.update(fingers(3), at: 0)
        #expect(e.tick(at: 2) == [])
    }

    @Test func enabledHoldFiresOnceWhenStill() {
        var config = GestureConfig()
        config.enabledHolds = [3]
        var e = GestureEngine(config: config)
        _ = e.update(fingers(1), at: 0)          // fingers land one after another:
        _ = e.update(fingers(3), at: 0.1)        // the hold is timed from the last one
        #expect(e.tick(at: 0.85) == [])
        #expect(e.tick(at: 0.95) == [.gesture(.hold(3))])
        #expect(e.tick(at: 1.5) == [])
        #expect(e.update([], at: 1.6) == [])     // lifting afterwards does nothing more
    }

    @Test func movingCancelsHold() {
        var config = GestureConfig()
        config.enabledHolds = [3]
        var e = GestureEngine(config: config)
        _ = e.update(fingers(3), at: 0)
        _ = e.update(fingers(3, x: 330), at: 0.3)
        #expect(e.tick(at: 1.0) == [])
    }

    @Test func fiveFingerHoldOpensPanel() {
        var e = GestureEngine()
        _ = e.update(fingers(5), at: 0)
        #expect(e.tick(at: 1.9) == [])
        #expect(e.tick(at: 2.05) == [.openPanel])
        #expect(e.update([], at: 2.2) == [])
    }

    @Test func threeFingerTap() {
        var e = GestureEngine()
        _ = e.update(fingers(3), at: 0)
        #expect(e.update([], at: 0.15) == [.gesture(.tap(3))])
    }

    @Test func scrollSpeedScalesScrolling() {
        var config = GestureConfig()
        config.scrollSpeed = 2
        var e = GestureEngine(config: config)
        _ = e.update(pair(gap: 100), at: 0)
        _ = e.update(pair(gap: 100).map { CGPoint(x: $0.x, y: $0.y + 20) }, at: 0.05)
        let changed = e.update(pair(gap: 100).map { CGPoint(x: $0.x, y: $0.y + 25) }, at: 0.06)
        #expect(changed == [.scroll(dx: 0, dy: 10, at: CGPoint(x: 400, y: 325), phase: .changed)])
    }

    @Test func inertiaCanBeTurnedOff() {
        var config = GestureConfig()
        config.inertia = false
        var e = GestureEngine(config: config)
        let lift = scrollDown(&e, speed: 1500)
        _ = e.update([], at: lift)
        #expect(glide(&e, from: lift, seconds: 0.5).isEmpty)
    }
}

@Suite struct SettingsTests {
    @Test func defaultsKeepTheOriginalSwipes() {
        let s = Settings()
        #expect(s.action(for: .swipe(3, .up)) == .system(.missionControl))
        #expect(s.action(for: .swipe(4, .left)) == .system(.nextTab))
        #expect(s.action(for: .hold(2)) == .none)
    }

    @Test func roundTripsThroughJSON() throws {
        var s = Settings()
        s.scrollSpeed = 1.7
        s.setAction(.keys(KeyCombo(keyCode: 3, modifiers: 1 << 20, display: "⌘F")), for: .hold(3))
        s.setAction(.openApp(path: "/Applications/Safari.app"), for: .tap(4))
        s.setAction(.none, for: .swipe(3, .up))
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        #expect(decoded.action(for: .swipe(3, .up)) == .none)  // an explicit "Nothing" overrides the default
    }

    @Test func missingFieldsUseDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"scrollSpeed": 2}"#.utf8))
        #expect(s.scrollSpeed == 2)
        #expect(s.glideLength == Settings().glideLength)
        #expect(s.action(for: .swipe(3, .down)) == .system(.appExpose))
    }

    @Test func holdsTurnOnWhenTheyHaveAnAction() {
        var s = Settings()
        s.setAction(.system(.showDesktop), for: .hold(4))
        #expect(GestureConfig(settings: s).enabledHolds == [4])
    }

    @Test func slotIDsAreUnique() {
        let ids = GestureSlot.configurable.map(\.id)
        #expect(Set(ids).count == ids.count && ids.count == 13)
    }
}

@Suite struct TouchAreaTests {
    let center = CGPoint(x: 100, y: 100)

    @Test func noRadiusNoSamples() {
        #expect(TouchArea.samplePoints(around: center, radius: 0).isEmpty)
    }

    @Test func samplesGoOutwardWithinRadius() {
        let points = TouchArea.samplePoints(around: center, radius: 24)
        let distances = points.map { hypot($0.x - center.x, $0.y - center.y) }
        #expect(distances.allSatisfy { $0 <= 24.001 && $0 >= 7.999 })
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 + 0.001 })  // nearest first
        #expect(points.count == 8 + 13 + 19)  // rings at 8, 16, 24 pt, ~8 pt apart
    }

    @Test func nearestPointClampsIntoTheFrame() {
        let button = CGRect(x: 120, y: 90, width: 60, height: 20)
        #expect(TouchArea.nearestPoint(in: button, to: center) == CGPoint(x: 123, y: 100))
        #expect(TouchArea.nearestPoint(in: button, to: CGPoint(x: 150, y: 50)) == CGPoint(x: 150, y: 93))
    }

    @Test func accuracySettingsDefaultOff() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(s.touchArea == 0 && s.touchOffsetX == 0 && s.touchOffsetY == 0)
    }
}
