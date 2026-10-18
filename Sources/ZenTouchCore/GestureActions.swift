public enum SwipeDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right
}

/// A gesture whose action you can choose in the panel.
public enum GestureSlot: Hashable, Codable, Sendable {
    /// Rest this many fingers (2...4) still on the screen.
    case hold(Int)
    /// Quick tap with this many fingers (3 or 4).
    case tap(Int)
    /// Swipe with this many fingers (3 or 4).
    case swipe(Int, SwipeDirection)

    public static let configurable: [GestureSlot] =
        [2, 3, 4].map { .hold($0) } + [3, 4].map { .tap($0) }
        + [3, 4].flatMap { n in SwipeDirection.allCases.map { .swipe(n, $0) } }

    /// Stable key for the settings file, e.g. "hold2", "tap3", "swipe4.left".
    public var id: String {
        switch self {
        case .hold(let n): "hold\(n)"
        case .tap(let n): "tap\(n)"
        case .swipe(let n, let d): "swipe\(n).\(d.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .hold(let n): "Hold \(n) fingers"
        case .tap(let n): "\(n)-finger tap"
        case .swipe(let n, let d): "\(n)-finger swipe \(d.rawValue)"
        }
    }
}

/// Built-in macOS actions a gesture can trigger.
public enum SystemAction: String, Codable, CaseIterable, Sendable {
    case missionControl, appExpose, showDesktop, apps, nextSpace, previousSpace
    case nextTab, previousTab, newTab, closeTab, reopenTab, back, forward
    case spotlight, screenshot, fullScreen, minimizeWindow, hideApp, lockScreen
    case copy, paste, undo, redo
    case zoomIn, zoomOut, actualSize
    case rightClick, middleClick
    case volumeUp, volumeDown, mute, playPause, nextTrack, previousTrack

    public var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé (app windows)"
        case .showDesktop: "Show Desktop"
        case .apps: "Apps (Launchpad)"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab / Window"
        case .reopenTab: "Reopen Closed Tab"
        case .back: "Back"
        case .forward: "Forward"
        case .spotlight: "Spotlight"
        case .screenshot: "Screenshot / Recording"
        case .fullScreen: "Toggle Full Screen"
        case .minimizeWindow: "Minimize Window"
        case .hideApp: "Hide App"
        case .lockScreen: "Lock Screen"
        case .copy: "Copy"
        case .paste: "Paste"
        case .undo: "Undo"
        case .redo: "Redo"
        case .zoomIn: "Zoom In (⌘+)"
        case .zoomOut: "Zoom Out (⌘−)"
        case .actualSize: "Actual Size (⌘0)"
        case .rightClick: "Right Click"
        case .middleClick: "Middle Click (open link in new tab)"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        }
    }

    /// Menu groups, in display order.
    public static let groups: [(title: String, actions: [SystemAction])] = [
        ("Desktop", [.missionControl, .appExpose, .showDesktop, .apps, .nextSpace, .previousSpace]),
        ("Browser & tabs", [.nextTab, .previousTab, .newTab, .closeTab, .reopenTab, .back, .forward]),
        ("Windows & system", [.spotlight, .screenshot, .fullScreen, .minimizeWindow, .hideApp, .lockScreen]),
        ("Editing", [.copy, .paste, .undo, .redo]),
        ("Zoom", [.zoomIn, .zoomOut, .actualSize]),
        ("Mouse", [.rightClick, .middleClick]),
        ("Media", [.volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .previousTrack]),
    ]
}

/// A recorded keyboard shortcut. `modifiers` uses CGEventFlags / NSEvent.ModifierFlags bits.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    /// What to show in the panel, e.g. "⌃⌘F".
    public var display: String

    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// Chosen in the panel but not recorded yet; does nothing.
    public static let unset = KeyCombo(keyCode: .max, modifiers: 0, display: "")
    public var isSet: Bool { keyCode != .max }
}

public enum GestureAction: Codable, Hashable, Sendable {
    case none
    case system(SystemAction)
    case keys(KeyCombo)
    case openApp(path: String)

    public var title: String {
        switch self {
        case .none: "Nothing"
        case .system(let action): action.title
        case .keys(let combo): combo.isSet ? "Shortcut \(combo.display)" : "Shortcut (not recorded)"
        case .openApp(let path): "Open \(path.split(separator: "/").last.map { $0.replacingOccurrences(of: ".app", with: "") } ?? path)"
        }
    }
}

/// The gestures that aren't configurable, for the panel's reference list.
public enum BuiltInGestures {
    public static let list: [(gesture: String, action: String)] = [
        ("Tap", "Click (tap twice to double-click)"),
        ("Touch and move", "Drag"),
        ("Touch and hold", "Right click"),
        ("2-finger tap", "Right click"),
        ("2-finger move", "Scroll"),
        ("2-finger flick", "Scroll with inertia (touch to stop)"),
        ("2-finger pinch", "Zoom in / out"),
        ("Hold 5 fingers for 2 s", "Open this panel"),
    ]
}
