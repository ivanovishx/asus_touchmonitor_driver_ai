/// Everything you can change in the gestures panel. Saved as JSON; fields missing from an older file
/// fall back to their defaults, so adding settings never breaks an existing file.
public struct Settings: Codable, Equatable, Sendable {
    /// Multiplies scroll distance and flick speed.
    public var scrollSpeed = 1.0
    public var inertia = true
    /// Seconds for the inertia's speed to fall to 37%; larger glides further.
    public var glideLength = 0.4
    public var longPress = 0.6
    /// How long 2-4 fingers must rest still to trigger a hold gesture.
    public var holdDuration = 0.8
    public var zoomWithKeys = false
    public var swapXY = false
    public var flipX = false
    public var flipY = false
    /// Shift (points) added to every touch.
    public var touchOffsetX = 0.0
    public var touchOffsetY = 0.0
    /// Radius (points) within which a tap snaps onto a nearby button or link, like a phone. 0 = off.
    public var touchArea = 0.0
    /// Action per GestureSlot.id. Slots not listed use `defaultBindings`.
    public var bindings: [String: GestureAction] = [:]

    public static let defaultBindings: [String: GestureAction] = [
        "swipe3.up": .system(.missionControl),
        "swipe3.down": .system(.appExpose),
        "swipe3.left": .system(.nextSpace),
        "swipe3.right": .system(.previousSpace),
        "swipe4.up": .system(.missionControl),
        "swipe4.down": .system(.appExpose),
        "swipe4.left": .system(.nextTab),
        "swipe4.right": .system(.previousTab),
    ]

    public init() {}

    public func action(for slot: GestureSlot) -> GestureAction {
        bindings[slot.id] ?? Self.defaultBindings[slot.id] ?? .none
    }

    public mutating func setAction(_ action: GestureAction, for slot: GestureSlot) {
        bindings[slot.id] = action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed
        inertia = try c.decodeIfPresent(Bool.self, forKey: .inertia) ?? d.inertia
        glideLength = try c.decodeIfPresent(Double.self, forKey: .glideLength) ?? d.glideLength
        longPress = try c.decodeIfPresent(Double.self, forKey: .longPress) ?? d.longPress
        holdDuration = try c.decodeIfPresent(Double.self, forKey: .holdDuration) ?? d.holdDuration
        zoomWithKeys = try c.decodeIfPresent(Bool.self, forKey: .zoomWithKeys) ?? d.zoomWithKeys
        swapXY = try c.decodeIfPresent(Bool.self, forKey: .swapXY) ?? d.swapXY
        flipX = try c.decodeIfPresent(Bool.self, forKey: .flipX) ?? d.flipX
        flipY = try c.decodeIfPresent(Bool.self, forKey: .flipY) ?? d.flipY
        touchOffsetX = try c.decodeIfPresent(Double.self, forKey: .touchOffsetX) ?? d.touchOffsetX
        touchOffsetY = try c.decodeIfPresent(Double.self, forKey: .touchOffsetY) ?? d.touchOffsetY
        touchArea = try c.decodeIfPresent(Double.self, forKey: .touchArea) ?? d.touchArea
        bindings = try c.decodeIfPresent([String: GestureAction].self, forKey: .bindings) ?? d.bindings
    }

    public var calibration: Calibration {
        var c = Calibration()
        c.swapXY = swapXY
        c.flipX = flipX
        c.flipY = flipY
        c.offsetX = touchOffsetX
        c.offsetY = touchOffsetY
        return c
    }
}

extension GestureConfig {
    public init(settings: Settings) {
        self.init()
        scrollSpeed = settings.scrollSpeed
        inertia = settings.inertia
        momentumTimeConstant = settings.glideLength
        longPress = settings.longPress
        holdDuration = settings.holdDuration
        // A hold only takes over when it does something, so resting fingers before a scroll still works.
        enabledHolds = Set((2...4).filter { settings.action(for: .hold($0)) != .none })
    }
}
