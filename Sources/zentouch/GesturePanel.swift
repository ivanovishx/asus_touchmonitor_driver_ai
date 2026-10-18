import AppKit
import SwiftUI
import ZenTouchCore

/// The gestures & settings window. Opened by holding 5 fingers, or from the menu bar.
final class GesturePanelController {
    private let store: SettingsStore
    private let displayQuery: String
    private var window: NSWindow?

    init(store: SettingsStore, displayQuery: String) {
        self.store = store
        self.displayQuery = displayQuery
    }

    /// Draws the panel (on the given tab) into a PNG, for checking the layout without a screenshot.
    func snapshot(tab: Int, to url: URL) throws {
        let window = makeWindow(tab: tab)
        window.orderFront(nil)
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // Open where the fingers are: centred on the touch display.
        let screen = NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains(displayQuery) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(tab: Int = 0) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: GesturePanelView(store: store, tab: tab)))
        window.title = "ZenTouch Gestures"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 760, height: 720))
        window.isReleasedWhenClosed = false
        return window
    }
}

struct GesturePanelView: View {
    @ObservedObject var store: SettingsStore
    @State private var tab: Int

    init(store: SettingsStore, tab: Int = 0) {
        self.store = store
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GesturesTab(store: store).tabItem { Text("Gestures") }.tag(0)
            SettingsTab(store: store).tabItem { Text("Settings") }.tag(1)
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 560)
        .controlSize(.large)  // easier to hit with a finger
    }
}

// MARK: - Gestures

struct GesturesTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Built-in gestures") {
                ForEach(BuiltInGestures.list, id: \.gesture) { item in
                    LabeledContent(item.gesture, value: item.action)
                }
            }
            Section {
                ForEach(GestureSlot.configurable, id: \.id) { slot in
                    ActionRow(slot: slot, holdDuration: store.settings.holdDuration, action: Binding(
                        get: { store.settings.action(for: slot) },
                        set: { store.settings.setAction($0, for: slot) }
                    ))
                }
            } header: {
                Text("Customizable gestures")
            } footer: {
                Text("A hold only does something once you give it an action. While it has one, resting that many fingers triggers it instead of waiting for a scroll or swipe.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// What kind of action a picker row has selected.
private enum ActionKind: Hashable {
    case none, system(SystemAction), keys, openApp
}

struct ActionRow: View {
    let slot: GestureSlot
    let holdDuration: Double
    @Binding var action: GestureAction

    private var kind: ActionKind {
        switch action {
        case .none: .none
        case .system(let s): .system(s)
        case .keys: .keys
        case .openApp: .openApp
        }
    }

    private var hint: String {
        switch slot {
        case .hold(let n): "Rest \(n) fingers still for \(String(format: "%.1f", holdDuration)) s"
        case .tap(let n): "Tap quickly with \(n) fingers"
        case .swipe(let n, let d): "Slide \(n) fingers \(d.rawValue)"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title).font(.headline)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch action {
            case .keys(let combo):
                ShortcutRecorder(combo: Binding(get: { combo }, set: { action = .keys($0) }))
            case .openApp(let path):
                Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) { chooseApp() }
            default:
                EmptyView()
            }
            Picker("Action", selection: Binding(get: { kind }, set: select)) {
                Text("Nothing").tag(ActionKind.none)
                ForEach(SystemAction.groups, id: \.title) { group in
                    Divider()
                    ForEach(group.actions, id: \.self) { a in
                        Text(a.title).tag(ActionKind.system(a))
                    }
                }
                Divider()
                Text("Keyboard Shortcut…").tag(ActionKind.keys)
                Text("Open App…").tag(ActionKind.openApp)
            }
            .labelsHidden()
            .frame(width: 250)
        }
        .padding(.vertical, 4)
    }

    private func select(_ kind: ActionKind) {
        switch kind {
        case .none: action = .none
        case .system(let s): action = .system(s)
        case .keys: if case .keys = action {} else { action = .keys(.unset) }
        case .openApp: chooseApp()
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for “\(slot.title)”"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            action = .openApp(path: url.path)
        }
    }
}

/// Click, then press the shortcut. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    @State private var monitor: Any?

    var body: some View {
        Button(monitor != nil ? "Press shortcut…" : combo.isSet ? combo.display : "Record Shortcut") {
            monitor == nil ? start() : stop()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.keyCode != 53 || !modifiers.isEmpty {  // a bare Esc cancels
                combo = KeyCombo(keyCode: event.keyCode, modifiers: UInt64(modifiers.rawValue),
                                 display: Self.describe(event, modifiers))
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static let keyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func describe(_ event: NSEvent, _ modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (keyNames[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?")
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Scrolling") {
                SliderRow(title: "Scroll speed", value: $store.settings.scrollSpeed, range: 0.5...3, format: "%.1f×")
                Toggle("Keep gliding after a flick (inertia)", isOn: $store.settings.inertia)
                SliderRow(title: "Glide length", value: $store.settings.glideLength, range: 0.15...0.8, format: "%.2f s")
                    .disabled(!store.settings.inertia)
            }
            Section("Timing") {
                SliderRow(title: "Touch and hold for right click", value: $store.settings.longPress, range: 0.3...1.5, format: "%.1f s")
                SliderRow(title: "Multi-finger hold", value: $store.settings.holdDuration, range: 0.4...2, format: "%.1f s")
            }
            Section("Zoom") {
                Picker("Pinch zoom", selection: $store.settings.zoomWithKeys) {
                    Text("Smooth, like a trackpad").tag(false)
                    Text("In steps (⌘+ / ⌘−)").tag(true)
                }
            }
            Section("Touch panel") {
                Toggle("Swap X and Y axes", isOn: $store.settings.swapXY)
                Toggle("Mirror horizontally", isOn: $store.settings.flipX)
                Toggle("Mirror vertically", isOn: $store.settings.flipY)
            }
            Section {
                Button("Restore Defaults", role: .destructive) { store.settings = Settings() }
            } footer: {
                Text("Settings are saved automatically to \(SettingsStore.fileURL.path).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range).frame(minWidth: 200)
                Text(String(format: format, value)).monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}
